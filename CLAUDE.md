# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

ComfyUI Docker Stack — Docker deployment of ComfyUI optimized for low-VRAM GPUs (8 GB). Wraps custom nodes into a single image:

- **ComfyUI-MultiGPU** (pollockjj) — DisTorch2 virtual VRAM: offloads idle model layers to system RAM or a second GPU
- **ComfyUI-GGUF** (city96) — quantized model loaders (Q4_K_S, Q5_K_M, etc.) that shrink model memory footprint
- **ComfyUI-TRELLIS2** (PozzettiAndrea) — 3D mesh generation from images/text using Microsoft TRELLIS 2 models; has its own VRAM management (sequential sub-model loading/unloading). Requires sibling node **ComfyUI-GeometryPack**.
- **ComfyUI-Manager** (ltdrdata) — UI-based node installer

This is an orchestration/deployment project, not a library. The actual application code lives inside the container (ComfyUI core + custom nodes cloned at build time).

## Build & Run

```bash
mkdir -p data/{models,input,output,user,custom_nodes}
docker compose build
docker compose up -d
docker compose logs -f comfyui    # watch startup
```

UI at http://localhost:8188

## Stack

- Base image: `nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04` (devel needed for flash-attn CUDA kernel compilation)
- Python 3.11, PyTorch from `whl/cu124`
- ComfyUI pinnable via `COMFYUI_REF` build arg (default: `master`)
- Non-root container user (UID/GID configurable)
- 8 GB shared memory for PyTorch

## Key Architecture Decisions

- **Additive custom nodes**: MultiGPU/GGUF loaders (`*DisTorch2MultiGPU` variants) don't replace standard ComfyUI loaders. Existing workflows keep working; users opt in per-workflow.
- **Models on volumes, not in image**: `./data/models/` is bind-mounted. Models are never baked into the Docker image.
- **User-installed nodes persist**: `./data/custom_nodes/` mounts to `/opt/ComfyUI/custom_nodes/_user`, surviving rebuilds.
- **Extra ComfyUI flags via env var**: `COMFY_ARGS` in docker-compose.yml forwards to the CMD (e.g. `--lowvram`, `--reserve-vram 0.5`).

## File Layout

```
Dockerfile            # Image definition
docker-compose.yml    # Build + run config (GPU, volumes, env)
README.md             # User-facing docs
data/                 # Host-side persistent storage (gitignored)
  models/             # checkpoints, unet, unet_gguf, clip, clip_gguf, vae, loras, controlnet
  input/              # Workflow input images
  output/             # Generated images
  user/               # ComfyUI user data
  custom_nodes/       # Nodes installed via Manager
```

## Hardware Assumptions

- Single NVIDIA GPU with 8 GB VRAM (Ampere/Ada fine on CUDA 12.4; Blackwell compute_cap 12.0 needs CUDA 12.8+ base image bump)
- `nvidia-container-toolkit` on host
- Sufficient system RAM for virtual VRAM (rule of thumb: `virtual_vram_gb` should not exceed RAM/2)

## Low-VRAM Strategy (ordered by impact)

1. GGUF-quantized model (e.g. Flux dev Q4_K_S: ~24 GB down to ~6-7 GB)
2. DisTorch2 loader with `virtual_vram_gb=6-10`, `donor_device=cpu`
3. `--lowvram` flag (or `--novram` as last resort)
4. `--reserve-vram 0.5` if desktop compositor needs headroom
5. Tiled VAE decode for high-res outputs
