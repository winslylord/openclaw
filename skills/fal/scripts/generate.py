#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Generate images using fal.ai cloud API.

Supports multiple models: flux/schnell (fast), flux/dev, flux-pro,
recraft-v3, and any other fal.ai model endpoint.

Usage:
    uv run generate.py --prompt "a cat in space" --filename "cat.png"
    uv run generate.py --model fal-ai/flux/dev --prompt "..." --filename "out.png"
"""

import argparse
import os
import random
import sys
import time
from pathlib import Path
from urllib.parse import urlparse

import requests

POLL_INTERVAL = 1.0
REQUEST_TIMEOUT = 60

MODEL_ALIASES: dict[str, str] = {
    "schnell": "fal-ai/flux/schnell",
    "flux-schnell": "fal-ai/flux/schnell",
    "dev": "fal-ai/flux/dev",
    "flux-dev": "fal-ai/flux/dev",
    "pro": "fal-ai/flux-pro/v1.1",
    "flux-pro": "fal-ai/flux-pro/v1.1",
    "recraft": "fal-ai/recraft-v3",
    "recraft-v3": "fal-ai/recraft-v3",
}

IMAGE_SIZE_PRESETS: dict[str, dict[str, int]] = {
    "square": {"width": 512, "height": 512},
    "square_hd": {"width": 1024, "height": 1024},
    "portrait_4_3": {"width": 768, "height": 1024},
    "portrait_16_9": {"width": 576, "height": 1024},
    "landscape_4_3": {"width": 1024, "height": 768},
    "landscape_16_9": {"width": 1024, "height": 576},
}

NAMED_SIZES = {"square_hd", "square", "portrait_4_3", "portrait_16_9", "landscape_4_3", "landscape_16_9"}


def resolve_api_key(provided: str | None) -> str:
    if provided:
        return provided
    key = os.environ.get("FAL_KEY", "")
    if not key:
        print("Error: fal.ai API key not set. Use --key or set FAL_KEY env var.", file=sys.stderr)
        sys.exit(1)
    return key


def resolve_model(alias: str) -> str:
    return MODEL_ALIASES.get(alias.lower(), alias)


def build_image_size(size: str | None, width: int | None, height: int | None) -> str | dict[str, int]:
    """Return either a named preset string or a {width, height} dict."""
    if width and height:
        return {"width": width, "height": height}
    if size:
        if size in NAMED_SIZES:
            return size
        if "x" in size:
            parts = size.split("x")
            return {"width": int(parts[0]), "height": int(parts[1])}
        return size
    return "landscape_4_3"


class QueueHandle:
    """URLs returned by fal.ai queue submit."""
    def __init__(self, request_id: str, status_url: str, response_url: str):
        self.request_id = request_id
        self.status_url = status_url
        self.response_url = response_url


def submit_request(api_key: str, model: str, arguments: dict) -> QueueHandle:
    """Submit a generation request to the fal.ai queue."""
    url = f"https://queue.fal.run/{model}"
    headers = {
        "Authorization": f"Key {api_key}",
        "Content-Type": "application/json",
    }
    resp = requests.post(url, json=arguments, headers=headers, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    data = resp.json()
    request_id = data.get("request_id")
    if not request_id:
        raise RuntimeError(f"No request_id in response: {data}")
    return QueueHandle(
        request_id=request_id,
        status_url=data.get("status_url", ""),
        response_url=data.get("response_url", ""),
    )


def poll_status(api_key: str, handle: QueueHandle) -> dict:
    """Poll the queue until the request completes.

    Uses the status_url returned by submit (which excludes model subpaths)
    to avoid 405 errors on models with subpaths like fal-ai/flux/schnell.
    """
    url = handle.status_url
    if not url:
        raise RuntimeError("No status_url in queue handle; cannot poll.")
    headers = {"Authorization": f"Key {api_key}"}

    while True:
        resp = requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT, params={"logs": "1"})
        resp.raise_for_status()
        status = resp.json()
        queue_status = status.get("status", "UNKNOWN")

        if queue_status == "COMPLETED":
            return status
        if queue_status in ("FAILED", "CANCELLED"):
            raise RuntimeError(f"Request {queue_status}: {status}")

        logs = status.get("logs", [])
        for log in logs:
            msg = log.get("message", "")
            if msg:
                print(f"  [{queue_status}] {msg}")

        queue_pos = status.get("queue_position")
        if queue_pos is not None:
            print(f"  Queue position: {queue_pos}")

        time.sleep(POLL_INTERVAL)


def fetch_result(api_key: str, handle: QueueHandle) -> dict:
    """Fetch the completed result using the response_url from submit."""
    url = handle.response_url
    if not url:
        raise RuntimeError("No response_url in queue handle; cannot fetch result.")
    headers = {"Authorization": f"Key {api_key}"}
    resp = requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT)
    resp.raise_for_status()
    return resp.json()


def download_image(url: str, output_path: Path, api_key: str) -> None:
    """Download an image from a URL to a local file."""
    headers = {}
    parsed = urlparse(url)
    if parsed.hostname and "fal" in parsed.hostname:
        headers["Authorization"] = f"Key {api_key}"

    with open(output_path, "wb") as f:
        # fal.ai URLs can be slow/large; use a generous timeout for the stream
        with requests.get(url, headers=headers, stream=True, timeout=(30, 300)) as resp:
            resp.raise_for_status()
            for chunk in resp.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)


def main():
    parser = argparse.ArgumentParser(description="Generate images via fal.ai cloud API")
    parser.add_argument("--prompt", "-p", required=True, help="Image generation prompt")
    parser.add_argument("--filename", "-f", required=True, help="Output filename")
    parser.add_argument("--model", "-m", default="schnell",
                        help="Model name or alias: schnell, dev, pro, recraft, or full fal-ai/* path (default: schnell)")
    parser.add_argument("--negative", "-n", default="", help="Negative prompt (model-dependent)")
    parser.add_argument("--size", "-S", default=None,
                        help="Image size preset (square_hd, landscape_4_3, portrait_16_9, etc.) or WxH (e.g. 1280x720)")
    parser.add_argument("--width", "-W", type=int, default=None, help="Image width (overrides --size)")
    parser.add_argument("--height", "-H", type=int, default=None, help="Image height (overrides --size)")
    parser.add_argument("--steps", type=int, default=None, help="Inference steps (model-dependent, schnell default: 4)")
    parser.add_argument("--cfg", type=float, default=None, help="Guidance scale (default: 3.5)")
    parser.add_argument("--seed", "-s", type=int, default=None, help="RNG seed for reproducibility")
    parser.add_argument("--num-images", type=int, default=1, help="Number of images to generate (default: 1)")
    parser.add_argument("--format", default="png", choices=["png", "jpeg"], help="Output format (default: png)")
    parser.add_argument("--key", "-k", default=None, help="fal.ai API key (or set FAL_KEY env var)")
    parser.add_argument("--timeout", type=int, default=300, help="Max wait seconds (default: 300)")
    parser.add_argument("--no-safety", action="store_true", help="Disable safety checker")
    parser.add_argument("--list-models", action="store_true", help="Show available model aliases and exit")

    args = parser.parse_args()

    if args.list_models:
        print("=== Available Model Aliases ===\n")
        seen = set()
        for alias, full_name in sorted(MODEL_ALIASES.items()):
            if full_name not in seen:
                print(f"  {alias:<16} → {full_name}")
                seen.add(full_name)
            else:
                print(f"  {alias:<16} → {full_name} (alias)")
        print("\nYou can also pass any full fal-ai model path, e.g.: fal-ai/flux/schnell")
        return

    api_key = resolve_api_key(args.key)
    model = resolve_model(args.model)
    seed = args.seed if args.seed is not None else random.randint(0, 2**32 - 1)
    image_size = build_image_size(args.size, args.width, args.height)

    arguments: dict = {
        "prompt": args.prompt,
        "seed": seed,
        "image_size": image_size,
        "num_images": args.num_images,
        "output_format": args.format,
        "enable_safety_checker": not args.no_safety,
    }

    if args.steps is not None:
        arguments["num_inference_steps"] = args.steps

    if args.cfg is not None:
        arguments["guidance_scale"] = args.cfg

    if args.negative:
        arguments["negative_prompt"] = args.negative

    print(f"Model: {model}")
    print(f"Prompt: {args.prompt}")
    if args.negative:
        print(f"Negative: {args.negative}")
    print(f"Size: {image_size}, Seed: {seed}, Format: {args.format}")
    if args.steps:
        print(f"Steps: {args.steps}")
    print(f"Submitting to fal.ai...")

    try:
        handle = submit_request(api_key, model, arguments)
        print(f"Queued: request_id={handle.request_id}")
    except Exception as e:
        print(f"Error submitting request: {e}", file=sys.stderr)
        sys.exit(1)

    print("Waiting for generation to complete...")
    deadline = time.time() + args.timeout

    try:
        poll_status(api_key, handle)
    except RuntimeError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    if time.time() > deadline:
        print(f"Error: generation timed out after {args.timeout}s", file=sys.stderr)
        sys.exit(1)

    result = fetch_result(api_key, handle)
    images = result.get("images", [])

    if not images:
        print("Error: no images returned.", file=sys.stderr)
        sys.exit(1)

    result_seed = result.get("seed", seed)
    print(f"Generation complete. Seed: {result_seed}")

    output_path = Path(args.filename)
    output_dir = output_path.parent if str(output_path.parent) != "." else Path.cwd()

    for i, img in enumerate(images):
        img_url = img.get("url", "")
        if not img_url:
            print(f"Warning: image {i} has no URL, skipping.", file=sys.stderr)
            continue

        if len(images) == 1:
            out_path = output_dir / output_path.name
        else:
            stem = output_path.stem
            suffix = output_path.suffix or f".{args.format}"
            out_path = output_dir / f"{stem}_{i}{suffix}"

        download_image(img_url, out_path, api_key)
        full_path = out_path.resolve()
        print(f"\nImage saved: {full_path}")
        print(f"MEDIA:{full_path}")


if __name__ == "__main__":
    main()
