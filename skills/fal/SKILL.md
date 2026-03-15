---
name: fal
description: Generate images and videos using fal.ai cloud API (Flux, Recraft, and more). Use when the user requests "Generate image", "Create video", "Text to image", or similar generation tasks.
homepage: https://fal.ai
metadata:
  {
    "openclaw":
      {
        "emoji": "🖼️",
        "requires": { "bins": ["curl"] },
      },
  }
---

# fal.ai (Cloud Image & Video Generation)

Generate images and videos using fal.ai's cloud API. Based on [fal-ai-community/skills](https://github.com/fal-ai-community/skills).

## Scripts

| Script | Purpose |
|--------|---------|
| `generate.sh` | **Primary** — Generate images/videos, download locally, output `MEDIA:` (bash + curl) |
| `upload.sh` | Upload local files to fal CDN |
| `search-models.sh` | Search and discover models |
| `get-schema.sh` | Get OpenAPI schema for any model |
| `generate.py` | Legacy Python alternative (requires `requests`; may hang behind HTTP proxies) |

## Quick Generate (recommended)

```bash
bash {baseDir}/scripts/generate.sh --prompt "your image description" --filename "/path/to/output.png"
```

This submits to fal.ai, polls until done, downloads the image locally, and outputs a `MEDIA:` line for OpenClaw auto-attachment.

Without `--filename`, the script outputs raw JSON with the CDN URL (no local download).

## Queue System (Default)

All requests use the queue system for reliability:

```
User Request → Queue Submit → Poll Status → Get Result
                   ↓
              request_id
```

Benefits: long-running tasks won't timeout, can check status/cancel anytime, results retrievable even if connection drops.

## Generate Content (bash)

```bash
# Image generation — download to local file (recommended for sending to chat)
bash {baseDir}/scripts/generate.sh --prompt "A serene mountain landscape" --filename "$HOME/.openclaw/media/landscape.png"

# Image generation — JSON output only (no download)
bash {baseDir}/scripts/generate.sh --prompt "A serene mountain landscape" --model "fal-ai/flux/schnell"

# Video generation
bash {baseDir}/scripts/generate.sh --prompt "Ocean waves crashing" --model "fal-ai/veo3.1" --filename "$HOME/.openclaw/media/waves.mp4"

# Image-to-Video
bash {baseDir}/scripts/generate.sh \
  --prompt "Camera slowly zooms in" \
  --model "fal-ai/kling-video/v2.6/pro/image-to-video" \
  --image-url "https://example.com/image.jpg" \
  --filename "$HOME/.openclaw/media/zoomed.mp4"
```

## Async Mode (Return Immediately)

```bash
# Submit and return immediately
bash {baseDir}/scripts/generate.sh --prompt "Epic battle scene" --model "fal-ai/veo3.1" --async

# Check status later
bash {baseDir}/scripts/generate.sh --status "request_id" --model "fal-ai/veo3.1"

# Get result when completed
bash {baseDir}/scripts/generate.sh --result "request_id" --model "fal-ai/veo3.1"

# Cancel if still queued
bash {baseDir}/scripts/generate.sh --cancel "request_id" --model "fal-ai/veo3.1"
```

## File Upload

```bash
# Option 1: Auto-upload with --file
bash {baseDir}/scripts/generate.sh \
  --file "/path/to/photo.jpg" \
  --model "fal-ai/kling-video/v2.6/pro/image-to-video" \
  --prompt "Camera zooms in slowly"

# Option 2: Manual upload
URL=$(bash {baseDir}/scripts/upload.sh --file "/path/to/photo.jpg")
bash {baseDir}/scripts/generate.sh --image-url "$URL" --model "..." --prompt "..."
```

## Generate Content (Python — legacy, not recommended)

> **Warning**: The Python script may hang when downloading images behind HTTP proxies.
> Use the bash script above instead.

```bash
# Requires: pip install requests (or uv run for auto-install)
python3 {baseDir}/scripts/generate.py --prompt "a cyberpunk cityscape" --filename "cyber.png"
```

## Finding Models

```bash
# Search by category
bash {baseDir}/scripts/search-models.sh --category "text-to-image"
bash {baseDir}/scripts/search-models.sh --category "text-to-video"

# Search by keyword
bash {baseDir}/scripts/search-models.sh --query "flux"
```

Categories: `text-to-image`, `image-to-image`, `text-to-video`, `image-to-video`, `text-to-speech`, `speech-to-text`

## Get Model Schema

```bash
bash {baseDir}/scripts/get-schema.sh --model "fal-ai/flux/schnell"
```

## Bash Script Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt`, `-p` | (required) | Text description |
| `--model`, `-m` | `fal-ai/flux/schnell` | Model ID |
| `--image-url` | - | Input image URL for I2V |
| `--file`, `--image` | - | Local file (auto-uploads) |
| `--size` | `landscape_4_3` | `square`, `portrait`, `landscape` |
| `--num-images` | `1` | Number of images |
| `--filename`, `-f` | - | Download result to local file and output `MEDIA:` line |
| `--async` | - | Return request_id immediately |
| `--sync` | - | Synchronous (not recommended for video) |
| `--logs` | - | Show generation logs while polling |
| `--status ID` | - | Check status of queued request |
| `--result ID` | - | Get result of completed request |
| `--cancel ID` | - | Cancel a queued request |
| `--poll-interval` | `2` | Seconds between status checks |
| `--timeout` | `600` | Max seconds to wait |
| `--lifecycle N` | - | Object expiration in seconds |
| `--schema MODEL` | - | Get OpenAPI schema |

## Python Script Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` / `-p` | (required) | Image generation prompt |
| `--filename` / `-f` | (required) | Output filename |
| `--model` / `-m` | `schnell` | Model alias or full `fal-ai/*` path |
| `--negative` / `-n` | `""` | Negative prompt |
| `--size` / `-S` | `landscape_4_3` | Size preset or `WxH` |
| `--width` / `-W` | (from size) | Image width |
| `--height` / `-H` | (from size) | Image height |
| `--steps` | (model default) | Inference steps |
| `--cfg` | `3.5` | Guidance scale |
| `--seed` / `-s` | random | RNG seed |
| `--num-images` | `1` | Number of images |
| `--format` | `png` | Output format: `png` or `jpeg` |
| `--key` / `-k` | `$FAL_KEY` | fal.ai API key |
| `--timeout` | `300` | Max wait seconds |
| `--list-models` | - | Show model aliases and exit |

## Python Model Aliases

| Alias | Full Path | Notes |
|-------|-----------|-------|
| `schnell` | `fal-ai/flux/schnell` | Ultra-fast, ~2s |
| `dev` | `fal-ai/flux/dev` | Higher quality, ~10s |
| `pro` | `fal-ai/flux-pro/v1.1` | Professional grade |
| `recraft` | `fal-ai/recraft-v3` | Vector art, text rendering |

## Output

**With `--filename` (recommended):**
```
MEDIA:/home/user/.openclaw/media/landscape.png
```
The script downloads the image and prints `MEDIA:<path>` to stdout. OpenClaw auto-attaches this file when sending to chat channels.

**Without `--filename`:**
```json
{
  "images": [{ "url": "https://v3.fal.media/files/...", "width": 1024, "height": 768 }]
}
```
Raw JSON with CDN URL — useful for chaining with other tools but requires manual download.

## Notes

- Always use `--filename` with a path under `~/.openclaw/media/` for chat delivery (OpenClaw enforces allowed media directories).
- Use timestamps in filenames: `yyyy-mm-dd-hh-mm-ss-name.png`.
- The `MEDIA:` output line is how OpenClaw auto-attaches files to chat channels (Feishu, Telegram, Discord, etc.).
- Do not read the image back; report the saved path only.
- When invoking via OpenClaw's exec tool, set a higher timeout (e.g., exec timeout=300).
- The fal.ai API requires an internet connection and a valid API key.
- The bash script loads `.env` from the scripts directory automatically (for `FAL_KEY`, proxy vars, etc.).

## Configuration

| Env Var | Description |
|---------|-------------|
| `FAL_KEY` | fal.ai API key (required) |

These can also be set via `skills.fal.env.*` in `~/.openclaw/openclaw.json`.
