# syntax=docker/dockerfile:1.7
# ComfyUI + MultiGPU + GGUF + TRELLIS2, built for low-VRAM cards (e.g. 8GB)
# Base: NVIDIA CUDA 12.4 devel with cuDNN on Ubuntu 22.04
# Note: devel (not runtime) is required because flash-attn compiles CUDA kernels at pip-install time.
FROM nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    # PyTorch / CUDA helpers
    TORCH_CUDA_ARCH_LIST="7.5;8.0;8.6;8.9;9.0" \
    # Make sure CUDA libs from python wheels are found
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:${LD_LIBRARY_PATH} \
    # Required by GeometryPack / TRELLIS2 (avoids MKL duplicate-lib errors)
    KMP_DUPLICATE_LIB_OK=TRUE \
    OMP_NUM_THREADS=1

# ---------- System deps ----------
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates wget aria2 \
        python3.11 python3.11-venv python3.11-dev python3-pip \
        build-essential ninja-build \
        libgl1 libglib2.0-0 libsm6 libxrender1 libxext6 \
        ffmpeg \
    && rm -rf /var/lib/apt/lists/* \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1 \
    && python -m pip install --upgrade pip wheel setuptools

# ---------- ComfyUI ----------
ARG COMFYUI_REF=master
WORKDIR /opt
RUN git clone https://github.com/comfyanonymous/ComfyUI.git && \
    cd ComfyUI && git checkout ${COMFYUI_REF}

WORKDIR /opt/ComfyUI

# PyTorch with CUDA 12.4 wheels
RUN pip install --index-url https://download.pytorch.org/whl/cu124 \
        torch torchvision torchaudio

# ComfyUI core requirements
RUN pip install -r requirements.txt

# Useful extras
RUN pip install \
        gguf \
        sentencepiece \
        accelerate \
        protobuf \
        opencv-python-headless \
        onnxruntime-gpu

# TRELLIS2 CUDA dependencies — flash-attn compiles kernels from source (~3-5 min with ninja).
# MAX_JOBS limits parallel compilation to avoid OOM on build hosts with limited RAM.
RUN pip install packaging ninja && \
    MAX_JOBS=4 pip install flash-attn --no-build-isolation && \
    pip install sageattention triton

# ---------- Custom nodes ----------
WORKDIR /opt/ComfyUI/custom_nodes

# ComfyUI-Manager (lets you install other nodes from the UI)
RUN git clone https://github.com/ltdrdata/ComfyUI-Manager.git && \
    pip install -r ComfyUI-Manager/requirements.txt || true

# ComfyUI-MultiGPU (DisTorch2 — the reason we're here)
RUN git clone https://github.com/pollockjj/ComfyUI-MultiGPU.git

# ComfyUI-GGUF (quantized model loaders — huge VRAM saver, pairs with MultiGPU)
RUN git clone https://github.com/city96/ComfyUI-GGUF.git && \
    pip install -r ComfyUI-GGUF/requirements.txt || true

# ComfyUI-GeometryPack (required dependency of TRELLIS2)
RUN git clone https://github.com/PozzettiAndrea/ComfyUI-GeometryPack.git && \
    pip install -r ComfyUI-GeometryPack/requirements.txt || true

# ComfyUI-TRELLIS2 (3D generation from images/text using TRELLIS 2 models)
RUN git clone https://github.com/PozzettiAndrea/ComfyUI-TRELLIS2.git && \
    pip install -r ComfyUI-TRELLIS2/requirements.txt || true

# ---------- Runtime layout ----------
WORKDIR /opt/ComfyUI

# These are the dirs you'll typically want as volumes
RUN mkdir -p \
    /opt/ComfyUI/models \
    /opt/ComfyUI/input \
    /opt/ComfyUI/output \
    /opt/ComfyUI/user

# Non-root user (optional but recommended)
ARG UID=1000
ARG GID=1000
RUN groupadd -g ${GID} comfy && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash comfy && \
    chown -R comfy:comfy /opt/ComfyUI
USER comfy

EXPOSE 8188

# --listen exposes the server on all interfaces inside the container.
# --use-pytorch-cross-attention is generally faster & uses less VRAM than xformers on modern PyTorch.
# Pass extra args via $COMFY_ARGS, e.g. -e COMFY_ARGS="--lowvram --reserve-vram 0.5"
ENV COMFY_ARGS=""
CMD ["sh", "-c", "python main.py --listen 0.0.0.0 --port 8188 --use-pytorch-cross-attention ${COMFY_ARGS}"]
