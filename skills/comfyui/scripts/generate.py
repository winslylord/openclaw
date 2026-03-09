#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "requests>=2.28.0",
# ]
# ///
"""
Generate images using a local ComfyUI instance.

Supports two model loading styles:
  - Flux-style: separate UNET + CLIP + VAE loaders (default when no checkpoints found)
  - Classic: single CheckpointLoaderSimple (when checkpoints are available)

Usage:
    uv run generate.py --prompt "a cat in space" --filename "cat.png"
    uv run generate.py --workflow my_workflow_api.json --prompt "override" --filename "out.png"
"""

import argparse
import json
import os
import random
import sys
import time
import uuid
from pathlib import Path
from urllib.parse import urlencode

import requests


DEFAULT_COMFYUI_URL = "http://127.0.0.1:8000"
REQUEST_TIMEOUT = 30
POLL_START_INTERVAL = 0.5
POLL_MAX_INTERVAL = 3.0


def get_comfyui_url(provided: str | None) -> str:
    if provided:
        return provided.rstrip("/")
    return os.environ.get("COMFYUI_URL", DEFAULT_COMFYUI_URL).rstrip("/")


def check_server(base_url: str) -> bool:
    try:
        r = requests.get(f"{base_url}/system_stats", timeout=5)
        return r.status_code == 200
    except Exception:
        return False


def query_node_options(base_url: str, node_class: str) -> dict | None:
    try:
        r = requests.get(f"{base_url}/object_info/{node_class}", timeout=REQUEST_TIMEOUT)
        r.raise_for_status()
        data = r.json()
        return data.get(node_class, {})
    except Exception:
        return None


def get_model_list(base_url: str, node_class: str, field: str) -> list[str]:
    info = query_node_options(base_url, node_class)
    if not info:
        return []
    try:
        return info["input"]["required"][field][0]
    except (KeyError, IndexError, TypeError):
        return []


def build_flux_workflow(
    prompt: str,
    negative: str,
    width: int,
    height: int,
    unet: str,
    clip: str,
    vae: str,
    seed: int,
    steps: int,
    cfg: float,
    sampler: str,
    scheduler: str,
) -> dict:
    """Flux-style workflow: separate UNETLoader + CLIPLoader + VAELoader."""
    return {
        "10": {
            "class_type": "UNETLoader",
            "inputs": {"unet_name": unet, "weight_dtype": "default"},
        },
        "11": {
            "class_type": "CLIPLoader",
            "inputs": {"clip_name": clip, "type": "flux2"},
        },
        "12": {
            "class_type": "VAELoader",
            "inputs": {"vae_name": vae},
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"batch_size": 1, "height": height, "width": width},
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["11", 0], "text": prompt},
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["11", 0], "text": negative},
        },
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": cfg,
                "denoise": 1.0,
                "latent_image": ["5", 0],
                "model": ["10", 0],
                "negative": ["7", 0],
                "positive": ["6", 0],
                "sampler_name": sampler,
                "scheduler": scheduler,
                "seed": seed,
                "steps": steps,
            },
        },
        "8": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["3", 0], "vae": ["12", 0]},
        },
        "9": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "OpenClaw", "images": ["8", 0]},
        },
    }


def build_checkpoint_workflow(
    prompt: str,
    negative: str,
    width: int,
    height: int,
    checkpoint: str,
    seed: int,
    steps: int,
    cfg: float,
    sampler: str,
    scheduler: str,
) -> dict:
    """Classic workflow: single CheckpointLoaderSimple."""
    return {
        "4": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": checkpoint},
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"batch_size": 1, "height": height, "width": width},
        },
        "6": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["4", 1], "text": prompt},
        },
        "7": {
            "class_type": "CLIPTextEncode",
            "inputs": {"clip": ["4", 1], "text": negative},
        },
        "3": {
            "class_type": "KSampler",
            "inputs": {
                "cfg": cfg,
                "denoise": 1.0,
                "latent_image": ["5", 0],
                "model": ["4", 0],
                "negative": ["7", 0],
                "positive": ["6", 0],
                "sampler_name": sampler,
                "scheduler": scheduler,
                "seed": seed,
                "steps": steps,
            },
        },
        "8": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["3", 0], "vae": ["4", 2]},
        },
        "9": {
            "class_type": "SaveImage",
            "inputs": {"filename_prefix": "OpenClaw", "images": ["8", 0]},
        },
    }


def inject_prompt_into_workflow(workflow: dict, prompt: str, negative: str | None) -> dict:
    """Find CLIPTextEncode nodes and inject prompt/negative via KSampler references."""
    positive_injected = False
    negative_injected = False

    ksampler_types = {"KSampler", "KSamplerAdvanced", "SamplerCustom"}
    positive_node_ids: set[str] = set()
    negative_node_ids: set[str] = set()

    for node in workflow.values():
        if node.get("class_type") not in ksampler_types:
            continue
        inputs = node.get("inputs", {})
        for key, ref_ids in [("positive", positive_node_ids), ("negative", negative_node_ids)]:
            ref = inputs.get(key)
            if isinstance(ref, list) and len(ref) >= 1:
                ref_ids.add(str(ref[0]))

    clip_nodes = [
        nid for nid, n in workflow.items()
        if n.get("class_type") == "CLIPTextEncode"
    ]

    for node_id in clip_nodes:
        node = workflow[node_id]
        if node_id in positive_node_ids and not positive_injected:
            node["inputs"]["text"] = prompt
            positive_injected = True
        elif node_id in negative_node_ids and negative is not None and not negative_injected:
            node["inputs"]["text"] = negative
            negative_injected = True

    if not positive_injected and clip_nodes:
        workflow[clip_nodes[0]]["inputs"]["text"] = prompt
        positive_injected = True

    if not positive_injected:
        print("Warning: could not find a CLIPTextEncode node to inject the prompt.", file=sys.stderr)

    return workflow


def submit_prompt(base_url: str, workflow: dict, client_id: str) -> str:
    payload = {"prompt": workflow, "client_id": client_id}
    r = requests.post(f"{base_url}/prompt", json=payload, timeout=REQUEST_TIMEOUT)
    r.raise_for_status()
    data = r.json()

    if "error" in data:
        detail = data.get("node_errors", "")
        raise RuntimeError(f"ComfyUI rejected the workflow: {data['error']}\n{detail}")

    return data["prompt_id"]


def wait_for_completion(base_url: str, prompt_id: str, timeout: int) -> dict:
    deadline = time.time() + timeout
    interval = POLL_START_INTERVAL

    while time.time() < deadline:
        try:
            r = requests.get(f"{base_url}/history/{prompt_id}", timeout=10)
            r.raise_for_status()
            history = r.json()

            if prompt_id in history:
                entry = history[prompt_id]
                status = entry.get("status", {})
                if status.get("status_str") == "error":
                    msgs = status.get("messages", [])
                    raise RuntimeError(f"ComfyUI execution failed: {msgs}")
                return entry
        except requests.RequestException:
            pass

        time.sleep(interval)
        interval = min(interval * 1.5, POLL_MAX_INTERVAL)

    raise TimeoutError(f"ComfyUI did not finish within {timeout}s")


def download_outputs(base_url: str, history_entry: dict, output_dir: Path, filename: str) -> list[Path]:
    outputs = history_entry.get("outputs", {})
    saved_paths: list[Path] = []

    for node_output in outputs.values():
        items = node_output.get("images", []) + node_output.get("gifs", [])
        for i, item in enumerate(items):
            params = urlencode({
                "filename": item["filename"],
                "subfolder": item.get("subfolder", ""),
                "type": item.get("type", "output"),
            })
            r = requests.get(f"{base_url}/view?{params}", timeout=60)
            r.raise_for_status()

            if len(items) == 1:
                out_path = output_dir / filename
            else:
                stem = Path(filename).stem
                suffix = Path(item["filename"]).suffix or Path(filename).suffix
                out_path = output_dir / f"{stem}_{i}{suffix}"

            out_path.parent.mkdir(parents=True, exist_ok=True)
            out_path.write_bytes(r.content)
            saved_paths.append(out_path)

    return saved_paths


def main():
    parser = argparse.ArgumentParser(description="Generate images via local ComfyUI")
    parser.add_argument("--prompt", "-p", required=True, help="Positive prompt text")
    parser.add_argument("--filename", "-f", required=True, help="Output filename")
    parser.add_argument("--negative", "-n", default="", help="Negative prompt")
    parser.add_argument("--width", "-W", type=int, default=1024, help="Image width")
    parser.add_argument("--height", "-H", type=int, default=1024, help="Image height")
    parser.add_argument("--checkpoint", "-c", default=None, help="Checkpoint filename (classic mode)")
    parser.add_argument("--unet", default=None, help="UNET/diffusion model filename (Flux mode)")
    parser.add_argument("--clip", default=None, help="CLIP model filename (Flux mode)")
    parser.add_argument("--vae", default=None, help="VAE model filename (Flux mode)")
    parser.add_argument("--workflow", "-w", default=None, help="Path to ComfyUI API-format workflow JSON")
    parser.add_argument("--url", default=None, help="ComfyUI server URL")
    parser.add_argument("--seed", "-s", type=int, default=None, help="RNG seed")
    parser.add_argument("--steps", type=int, default=20, help="Sampling steps")
    parser.add_argument("--cfg", type=float, default=7.0, help="CFG scale")
    parser.add_argument("--sampler", default="euler", help="Sampler name")
    parser.add_argument("--scheduler", default="normal", help="Scheduler name")
    parser.add_argument("--timeout", type=int, default=300, help="Max wait seconds")
    parser.add_argument("--list-models", action="store_true", help="List available models and exit")

    args = parser.parse_args()
    base_url = get_comfyui_url(args.url)

    if not check_server(base_url):
        print(f"Error: ComfyUI server is not reachable at {base_url}", file=sys.stderr)
        print("Please start ComfyUI first.", file=sys.stderr)
        sys.exit(1)

    checkpoints = get_model_list(base_url, "CheckpointLoaderSimple", "ckpt_name")
    unets = get_model_list(base_url, "UNETLoader", "unet_name")
    clips = get_model_list(base_url, "CLIPLoader", "clip_name")
    vaes = get_model_list(base_url, "VAELoader", "vae_name")

    if args.list_models:
        print("=== Available Models ===")
        print(f"\nCheckpoints: {checkpoints or '(none)'}")
        print(f"UNET/Diffusion: {unets or '(none)'}")
        print(f"CLIP: {clips or '(none)'}")
        print(f"VAE: {vaes or '(none)'}")
        return

    client_id = str(uuid.uuid4())
    seed = args.seed if args.seed is not None else random.randint(0, 2**32 - 1)

    print(f"ComfyUI server: {base_url}")

    if args.workflow:
        workflow_path = Path(args.workflow)
        if not workflow_path.exists():
            print(f"Error: workflow file not found: {args.workflow}", file=sys.stderr)
            sys.exit(1)
        workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
        workflow = inject_prompt_into_workflow(workflow, args.prompt, args.negative or None)
        print(f"Using custom workflow: {args.workflow}")

    elif args.checkpoint or (checkpoints and not unets):
        ckpt = args.checkpoint or checkpoints[0]
        print(f"Mode: classic (CheckpointLoaderSimple)")
        print(f"Checkpoint: {ckpt}")
        workflow = build_checkpoint_workflow(
            prompt=args.prompt, negative=args.negative,
            width=args.width, height=args.height,
            checkpoint=ckpt, seed=seed,
            steps=args.steps, cfg=args.cfg,
            sampler=args.sampler, scheduler=args.scheduler,
        )

    elif unets:
        unet = args.unet or unets[0]
        clip = args.clip or (clips[0] if clips else None)
        vae = args.vae or (vaes[0] if vaes else None)
        if not clip or not vae:
            print("Error: Flux mode requires CLIP and VAE models.", file=sys.stderr)
            sys.exit(1)
        print(f"Mode: Flux (UNET + CLIP + VAE)")
        print(f"UNET: {unet}")
        print(f"CLIP: {clip}")
        print(f"VAE:  {vae}")
        workflow = build_flux_workflow(
            prompt=args.prompt, negative=args.negative,
            width=args.width, height=args.height,
            unet=unet, clip=clip, vae=vae, seed=seed,
            steps=args.steps, cfg=args.cfg,
            sampler=args.sampler, scheduler=args.scheduler,
        )

    else:
        print("Error: no diffusion models found in ComfyUI.", file=sys.stderr)
        print("Install a checkpoint or UNET model first.", file=sys.stderr)
        sys.exit(1)

    print(f"Prompt: {args.prompt}")
    if args.negative:
        print(f"Negative: {args.negative}")
    print(f"Size: {args.width}x{args.height}, Seed: {seed}, Steps: {args.steps}")
    print("Submitting to ComfyUI...")

    try:
        prompt_id = submit_prompt(base_url, workflow, client_id)
        print(f"Queued: prompt_id={prompt_id}")
    except Exception as e:
        print(f"Error submitting prompt: {e}", file=sys.stderr)
        sys.exit(1)

    print("Waiting for generation to complete...")
    try:
        history_entry = wait_for_completion(base_url, prompt_id, args.timeout)
    except (TimeoutError, RuntimeError) as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    output_path = Path(args.filename)
    output_dir = output_path.parent if str(output_path.parent) != "." else Path.cwd()

    saved = download_outputs(base_url, history_entry, output_dir, output_path.name)

    if not saved:
        print("Error: no output images were generated.", file=sys.stderr)
        sys.exit(1)

    for p in saved:
        full_path = p.resolve()
        print(f"\nImage saved: {full_path}")
        print(f"MEDIA:{full_path}")


if __name__ == "__main__":
    main()
