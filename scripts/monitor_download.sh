#!/usr/bin/env bash
###############################################################################
# scripts/monitor_download.sh
#
# Background monitor for the HunyuanVideo checkpoint download (named container).
# Launch fully detached: setsid ./scripts/monitor_download.sh >> download_monitor.log 2>&1 < /dev/null &
#
# - Polls every 30 min, logs progress to download_monitor.log
# - Detects a stall (no byte growth between checks) and warns via desktop notify
# - When the downloader container exits, fires a desktop notification:
#     OK  -> "Download complete." found in docker logs
#     BAD -> container exited without the success marker (error/crash)
###############################################################################
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

CONTAINER="hunyuan_dl"
INTERVAL=1800          # 30 min between checks
PREV_BYTES=0
STALL_WARNED=0

while true; do
  RUNNING=$(docker ps --filter "name=${CONTAINER}" --format '{{.Names}}' | head -1)
  CUR_BYTES=$(du -sb ckpts 2>/dev/null | cut -f1)
  CUR_HUMAN=$(du -sh ckpts 2>/dev/null | cut -f1)
  TS=$(date '+%Y-%m-%d %H:%M')

  # --- download finished: container no longer in `docker ps` ---
  if [[ -z "${RUNNING}" ]]; then
    if docker logs "${CONTAINER}" 2>&1 | grep -q "Download complete."; then
      MSG="Descarga COMPLETA (${CUR_HUMAN} en ckpts). Listo para generar el video."
      notify-send -u critical -i dialog-information "HunyuanVideo: descarga OK" "${MSG}"
      echo "${TS} [DONE-OK] ${MSG}" >> download_monitor.log
    else
      LAST=$(docker logs "${CONTAINER}" 2>&1 | tr -d '\r' | tail -1)
      MSG="El container termino pero NO encontro 'Download complete'. Posible error. Ultima linea: ${LAST}"
      notify-send -u critical -i dialog-warning "HunyuanVideo: ATENCION descarga" "${MSG}"
      echo "${TS} [DONE-ERR] ${MSG}" >> download_monitor.log
    fi
    exit 0
  fi

  # --- still running: log progress ---
  echo "${TS} [running] ckpts=${CUR_HUMAN} container=${RUNNING}" >> download_monitor.log

  # --- stall detection (only after the first real sample) ---
  if [[ ${PREV_BYTES} -gt 0 && ${CUR_BYTES} -le ${PREV_BYTES} ]]; then
    echo "${TS} [WARN] sin crecimiento desde el chequeo anterior (posible stall)" >> download_monitor.log
    if [[ ${STALL_WARNED} -eq 0 ]]; then
      notify-send -u normal -i dialog-warning "HunyuanVideo: descarga lenta" \
        "ckpts sigue en ${CUR_HUMAN} — posible stall. Revisar docker logs ${CONTAINER}"
      STALL_WARNED=1
    fi
  else
    STALL_WARNED=0
  fi

  PREV_BYTES=${CUR_BYTES}
  sleep "${INTERVAL}"
done
