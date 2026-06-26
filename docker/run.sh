#!/usr/bin/env bash
# docker/run.sh -- convenience wrapper for a 720p text-to-video generation.
#
# Usage:
#   ./docker/run.sh "your prompt here" [extra generate.py args...]
#
# Requires: checkpoints already downloaded to ./ckpts AND the image built
# (`docker compose build`). Honors the compose service config (GPU, volumes,
# cap_drop). Any extra args are appended to generate.py.

set -euo pipefail

PROMPT="${1:?usage: ./docker/run.sh \"<prompt>\" [extra generate.py args...]}"
shift || true

docker compose run --rm inference \
    --prompt="${PROMPT}" \
    --resolution=720p \
    --model_path=/app/ckpts \
    --rewrite=false \
    --sr=true \
    --seed=123 \
    --output_path=/app/outputs/output_720p.mp4 \
    "$@"
