---
name: comfyui
description: Generate images and videos via a local ComfyUI instance.
homepage: https://github.com/comfyanonymous/ComfyUI
metadata:
  {
    "openclaw":
      {
        "emoji": "🎨",
        "requires": { "bins": ["uv"] },
      },
  }
---

# ComfyUI (Local Image & Video Generation)

Generate images using a locally running ComfyUI server.

## Quick Generate (auto-detect model style)

```bash
uv run {baseDir}/scripts/generate.py --prompt "your image description" --filename "output.png"
```

The script auto-detects whether to use Flux-style (UNET+CLIP+VAE) or classic (checkpoint) loading based on what models are installed.

## With options

```bash
uv run {baseDir}/scripts/generate.py --prompt "a cyberpunk cityscape at sunset" --negative "blurry, low quality" --filename "cyberpunk.png" --width 1024 --height 768 --steps 25
```

## Using a custom ComfyUI workflow (API format JSON)

Export a workflow from ComfyUI via `File → Export (API)` (requires Dev mode), then:

```bash
uv run {baseDir}/scripts/generate.py --workflow /path/to/workflow_api.json --prompt "override positive prompt" --filename "output.png"
```

The script auto-detects positive/negative prompt nodes and replaces their text.

## List available models

```bash
uv run {baseDir}/scripts/generate.py --list-models --prompt dummy --filename dummy
```

## Explicitly select models (Flux mode)

```bash
uv run {baseDir}/scripts/generate.py --prompt "..." --filename "out.png" --unet "z_image_turbo_bf16.safetensors" --clip "qwen_3_4b.safetensors" --vae "ae.safetensors"
```

## Options

| Flag | Default | Description |
|------|---------|-------------|
| `--prompt` / `-p` | (required) | Positive prompt text |
| `--filename` / `-f` | (required) | Output filename |
| `--negative` / `-n` | `""` | Negative prompt |
| `--width` / `-W` | `1024` | Image width |
| `--height` / `-H` | `1024` | Image height |
| `--checkpoint` / `-c` | (auto) | Checkpoint filename for classic mode |
| `--unet` | (auto) | UNET/diffusion model filename for Flux mode |
| `--clip` | (auto) | CLIP model filename for Flux mode |
| `--vae` | (auto) | VAE model filename for Flux mode |
| `--clip-type` | (auto) | CLIP type for CLIPLoader (e.g. `flux2`, `qwen_image`, `sd3`). Auto-detected from model name if omitted |
| `--workflow` / `-w` | (built-in) | Path to ComfyUI API-format workflow JSON |
| `--url` | `http://127.0.0.1:8000` | ComfyUI server URL |
| `--seed` / `-s` | random | RNG seed for reproducibility |
| `--steps` | `20` | Sampling steps |
| `--cfg` | `7.0` | CFG scale |
| `--sampler` | `euler` | Sampler name |
| `--scheduler` | `normal` | Scheduler name |
| `--timeout` | `300` | Max wait seconds for generation |
| `--list-models` | | List available models and exit |
| `--auto-start` | (auto) | Auto-start ComfyUI if not running (enabled by default when exe is found) |
| `--comfyui-exe` | (auto) | Path to ComfyUI executable |

## Auto-Start

When ComfyUI is not running, the script can automatically launch it:

- **Windows default**: auto-detects `C:\Users\winsl\AppData\Local\Programs\ComfyUI\ComfyUI.exe`
- **Custom path**: use `--comfyui-exe /path/to/ComfyUI` or set `COMFYUI_EXE` env var
- **Disable**: use `--auto-start` explicitly set to false via env, or ensure no exe path is configured

The script launches ComfyUI as a detached background process and polls `/system_stats` until the server is ready (up to 120 seconds).

## Notes

- Use timestamps in filenames: `yyyy-mm-dd-hh-mm-ss-name.png`.
- When `--filename` is a bare name (no directory), the script saves to `~/.openclaw/media/` automatically. This ensures the output is in the media allowlist and can be sent via any channel (Feishu, WhatsApp, etc.).
- The script prints a `MEDIA:` line for OpenClaw to auto-attach on supported chat providers.
- Do not read the image back; report the saved path only.
- When invoking via OpenClaw's exec tool, set a higher timeout to avoid premature termination (e.g., exec timeout=300). ComfyUI auto-start can take up to 120 seconds, plus generation time.
- If no model is explicitly specified, the script picks the first available one from ComfyUI.
- The script forces line-buffered stdout so progress appears in real-time even in non-TTY environments (exec tool, subprocess).

## Configuration

| Env Var | Description |
|---------|-------------|
| `COMFYUI_URL` | ComfyUI server URL (default: `http://127.0.0.1:8000`) |
| `COMFYUI_EXE` | Path to ComfyUI executable for auto-start |

These can also be set via `skills.comfyui.env.*` in `~/.openclaw/openclaw.json`.
