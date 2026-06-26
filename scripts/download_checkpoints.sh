#!/usr/bin/env bash
###############################################################################
# scripts/download_checkpoints.sh
#
# Downloads ALL checkpoints HunyuanVideo-1.5 needs into ./ckpts (relative to the
# repo root). Run THIS ON THE HOST, NOT inside the inference container.
#
# ---------------------------------------------------------------------------
# One-time host setup (NOT done automatically by this script):
#   pip install -U "huggingface_hub[cli]" modelscope
#
# This script is idempotent: `hf download` and `modelscope download` resume
# interrupted transfers, so re-running after a failure just continues.
#
# Layout produced (must match what the pipeline loads in source):
#   ckpts/                                  <- tencent/HunyuanVideo-1.5
#     transformer/{720p_t2v,...,720p_sr_distilled,1080p_sr_distilled}
#     vae/  scheduler/  upsampler/...
#     text_encoder/
#       llm/                                <- Qwen/Qwen2.5-VL-7B-Instruct
#       byt5-small/                         <- google/byt5-small
#       Glyph-SDXL-v2/                      <- AI-ModelScope/Glyph-SDXL-v2 (ModelScope)
#         assets/{color_idx,multilingual_10-lang_idx}.json
#         checkpoints/byt5_model.pt
#     vision_encoder/
#       siglip/                             <- black-forest-labs/FLUX.1-Redux-dev (GATED)
###############################################################################
set -euo pipefail

# Resolve repo root (parent of this script's directory) and work from there.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Load HF_TOKEN from .env (gitignored; see .env.example). NEVER commit a token.
# ---------------------------------------------------------------------------
if [[ -f .env ]]; then
    # shellcheck disable=SC1091
    set -o allexport
    source .env
    set +o allexport
fi

if [[ -z "${HF_TOKEN:-}" ]]; then
    echo "ERROR: HF_TOKEN is not set." >&2
    echo "       Create a .env file at the repo root containing:" >&2
    echo "           HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxx" >&2
    echo "       The token needs read access to black-forest-labs/FLUX.1-Redux-dev (gated)." >&2
    exit 1
fi

if [[ "${HF_TOKEN}" == "replace_with_your_huggingface_token" ]]; then
    echo "ERROR: HF_TOKEN in .env is still the placeholder." >&2
    echo "       Edit .env and paste your real HuggingFace token." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Verify required CLIs are installed on the host.
# ---------------------------------------------------------------------------
command -v hf >/dev/null 2>&1 || {
    echo "ERROR: 'hf' (huggingface CLI) not found." >&2
    echo "       Install once with:  pip install -U \"huggingface_hub[cli]\"" >&2
    exit 1
}
command -v modelscope >/dev/null 2>&1 || {
    echo "ERROR: 'modelscope' CLI not found." >&2
    echo "       Install once with:  pip install modelscope" >&2
    exit 1
}

echo "==[ 1/5 ] DiT + VAE + scheduler + SR transformers (tencent/HunyuanVideo-1.5)"
echo "    (optimized: only 720p_t2v + SR transformers + vae + scheduler)"
# Only download what a 720p T2V + SR run actually loads. Skipping 480p/I2V/distilled
# variants cuts ~200GB down to ~100GB and reduces hf download stall risk.
# --max-workers 4 lowers concurrency (default 8) for more stable long transfers.
hf download tencent/HunyuanVideo-1.5 --local-dir ./ckpts \
    --max-workers 4 \
    --include "transformer/720p_t2v/*" \
             "transformer/720p_sr_distilled/*" \
             "transformer/1080p_sr_distilled/*" \
             "vae/*" \
             "scheduler/*" \
             "config.json" \
             "assets/*"

echo "==[ 2/5 ] MLLM text encoder (Qwen/Qwen2.5-VL-7B-Instruct) -> ckpts/text_encoder/llm"
hf download Qwen/Qwen2.5-VL-7B-Instruct --local-dir ./ckpts/text_encoder/llm

echo "==[ 3/5 ] byT5 base (google/byt5-small) -> ckpts/text_encoder/byt5-small"
hf download google/byt5-small --local-dir ./ckpts/text_encoder/byt5-small

echo "==[ 4/5 ] Glyph-SDXL-v2 byT5 weights (ModelScope) -> ckpts/text_encoder/Glyph-SDXL-v2"
modelscope download --model AI-ModelScope/Glyph-SDXL-v2 --local_dir ./ckpts/text_encoder/Glyph-SDXL-v2

echo "==[ 5/5 ] Vision encoder / Siglip (GATED: black-forest-labs/FLUX.1-Redux-dev) -> ckpts/vision_encoder/siglip"
hf download black-forest-labs/FLUX.1-Redux-dev \
    --local-dir ./ckpts/vision_encoder/siglip \
    --token "${HF_TOKEN}"

# ---------------------------------------------------------------------------
# Sanity-check the byT5 layout the pipeline hard-requires (see _load_byt5).
# ---------------------------------------------------------------------------
GLYPH_CKPT="./ckpts/text_encoder/Glyph-SDXL-v2/checkpoints/byt5_model.pt"
if [[ ! -f "${GLYPH_CKPT}" ]]; then
    echo "WARNING: expected file not found: ${GLYPH_CKPT}" >&2
    echo "         The pipeline hard-fails unless Glyph-SDXL-v2 contains:" >&2
    echo "           assets/color_idx.json, assets/multilingual_10-lang_idx.json," >&2
    echo "           checkpoints/byt5_model.pt" >&2
fi

echo
echo "============================================================================"
echo "Download complete."
echo "Total disk used by ./ckpts:"
du -sh ./ckpts 2>/dev/null || true
echo "============================================================================"
