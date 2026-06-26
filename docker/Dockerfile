# syntax=docker/dockerfile:1.6

###############################################################################
# HunyuanVideo-1.5 inference image  (NVIDIA Blackwell / RTX 5090, sm_120)
###############################################################################

# --- Why this base image + torch trio --------------------------------------
# RTX 5090 is Blackwell (compute capability sm_120). PyTorch <= 2.6 -- the
# version `requirements.txt` loosely allows via `torch>=2.6.0` -- has NO sm_120
# kernels; CUDA kernels fail or hang on this GPU.
#
# We therefore pin a CUDA 12.8 ("cu128") torch build that ships Blackwell
# kernels. Blackwell (sm_120) support landed in PyTorch 2.9; we pick the LATEST
# stable cu128 trio available on the index for the most mature kernels:
#     torch==2.11.0+cu128, torchvision==0.26.0+cu128, torchaudio==2.11.0+cu128
# (If a regression ever appears with a brand-new torch, step the trio down to
#  2.9.1+cu128 / 0.24.1+cu128 / 2.9.1+cu128, which also fully supports sm_120.)
#
# `requirements.txt` pins `torchaudio==2.6.0`, which is INCOMPATIBLE with torch
# 2.11. We exclude torch/torchvision/torchaudio from requirements.txt (see the
# filtered install below) and install the matched cu128 trio first.
#
# Base image is the CUDA 12.8.1 *runtime* (NOT devel): we compile NO CUDA
# extensions in v1, so the devel toolchain is unnecessary and much larger.
#
# Optional future accelerations (NOT installed in v1 -- they need the devel
# image + compilation and Blackwell kernel support may lag):
#   flash-attention, sage-attention, flex-block-attn, sgl-kernel.
# The pipeline runs correctly WITHOUT them.
# ---------------------------------------------------------------------------

FROM nvidia/cuda:12.8.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    LANG=C.UTF-8

# ---------------------------------------------------------------------------
# System: Python 3.10 (Ubuntu 22.04 default), ffmpeg, git, minimal build tools
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv python3-dev \
        ffmpeg git curl ca-certificates \
        build-essential \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/python3 /usr/bin/python

# ---------------------------------------------------------------------------
# HuggingFace cache dirs (writable, inside the container) + CUDA allocator.
# Avoids permission issues; checkpoints are mounted read-only, never baked in.
# ---------------------------------------------------------------------------
ENV HF_HOME=/app/.cache/huggingface \
    HF_HUB_CACHE=/app/.cache/huggingface/hub \
    TRANSFORMERS_CACHE=/app/.cache/huggingface/transformers \
    PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

WORKDIR /app

# ---------------------------------------------------------------------------
# 1) Blackwell-compatible torch trio from the cu128 wheel index (FIRST)
# ---------------------------------------------------------------------------
RUN pip install --upgrade pip setuptools wheel && \
    pip install --no-cache-dir \
        torch==2.11.0 \
        torchvision==0.26.0 \
        torchaudio==2.11.0 \
        --index-url https://download.pytorch.org/whl/cu128

# ---------------------------------------------------------------------------
# 2) Remaining pinned deps, EXCLUDING torch/torchvision/torchaudio.
#    (Those three are provided above as the matched cu128 Blackwell trio.)
# ---------------------------------------------------------------------------
COPY requirements.txt /app/requirements.txt
RUN grep -ivE '^(torch|torchvision|torchaudio)(\W|$)' /app/requirements.txt \
        > /app/requirements.filtered.txt && \
    pip install --no-cache-dir -r /app/requirements.filtered.txt

# ---------------------------------------------------------------------------
# 3) Application code. Checkpoints are NEVER baked in (huge; mounted at runtime).
# ---------------------------------------------------------------------------
COPY . /app

# Entrypoint runs generate.py; pass all args via `command:` (compose) or `docker run`.
ENTRYPOINT ["python", "generate.py"]
# Safe no-op default so a bare `docker run` does not crash; override at runtime.
CMD ["--help"]
