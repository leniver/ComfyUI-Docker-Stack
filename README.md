# ComfyUI Docker Stack

Docker stack for ComfyUI with MultiGPU offloading, GGUF quantization, and TRELLIS2 3D generation — optimized for low-VRAM GPUs.

## Included nodes

- **[ComfyUI-MultiGPU](https://github.com/pollockjj/ComfyUI-MultiGPU)** — DisTorch2 distributes model layers across GPUs or offloads them to system RAM ("Virtual VRAM"). One 8GB card + 32GB RAM can run models that would otherwise OOM.
- **[ComfyUI-GGUF](https://github.com/city96/ComfyUI-GGUF)** — quantized model loaders (Q4_K_S, Q5_K_M, etc.). Flux dev goes from ~24GB to ~6–7GB at Q4 with very little quality loss.
- **[ComfyUI-TRELLIS2](https://github.com/PozzettiAndrea/ComfyUI-TRELLIS2)** — 3D mesh generation from images or text using Microsoft TRELLIS 2 models. Includes [ComfyUI-GeometryPack](https://github.com/PozzettiAndrea/ComfyUI-GeometryPack) as a dependency.
- **[ComfyUI-Manager](https://github.com/ltdrdata/ComfyUI-Manager)** — install more nodes from the UI without rebuilding.

## Prerequisites

On the host:
- NVIDIA driver (compatible with CUDA 12.4 — 550+ recommended)
- Docker 24+
- `nvidia-container-toolkit` installed and configured:
  ```bash
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  # sanity check:
  docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi
  ```

## Build & run

```bash
mkdir -p data/{models,input,output,user,custom_nodes}
docker compose build
docker compose up -d
docker compose logs -f comfyui
```

Then open <http://localhost:8188>.

## Where to put models

Inside `./data/models/...`:

```
data/models/
├── checkpoints/      # full safetensors checkpoints (SDXL etc.)
├── unet/             # diffusion-only UNet files (Flux, etc.)
├── unet_gguf/        # GGUF-quantized UNets ← put your Flux Q4/Q5 here
├── clip/
├── clip_gguf/        # GGUF-quantized text encoders
├── vae/
├── loras/
└── controlnet/
```

## Using MultiGPU with one 8GB card

In the workflow, swap normal loaders for their `*DisTorch2MultiGPU` variants:

- `CheckpointLoaderSimpleDisTorch2MultiGPU`
- `UNETLoaderDisTorch2MultiGPU` or `UnetLoaderGGUFDisTorch2MultiGPU`
- `DualCLIPLoaderDisTorch2MultiGPU` / `...GGUFDisTorch2MultiGPU`

Set:
- `compute_device` = `cuda:0` (your 8GB card)
- `virtual_vram_gb` = how much extra "VRAM" to borrow (start with 4–8)
- `donor_device` = `cpu` (system RAM) — or `cuda:1` if you have a second card

Effect: ComfyUI runs computation on `cuda:0`, but the model's idle layers live in RAM and get swapped in as needed. Slower than pure-GPU, but it actually fits.

## If it still OOMs

Pass extra flags via `COMFY_ARGS`:

```yaml
environment:
  COMFY_ARGS: "--lowvram --reserve-vram 0.8"
```

Stacking strategies (most to least impactful for 8GB):
1. Use a Q4_K_S **GGUF** version of the model.
2. Use the **DisTorch2** GGUF loader with `virtual_vram_gb` 6–10, `donor_device=cpu`.
3. Add `--lowvram` (or `--novram` as a last resort).
4. Add `--reserve-vram 0.5` if your desktop compositor needs headroom.
5. Use a tiled VAE node for decode.

## Customizing

- Pin a ComfyUI version: change `COMFYUI_REF` in `docker-compose.yml` to a commit SHA.
- Different CUDA: change the base image tag and the PyTorch `--index-url` (e.g. `cu121`).
- Rootless / different UID: edit the `UID`/`GID` build args to match `id -u` / `id -g` on the host.
