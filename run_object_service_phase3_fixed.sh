#!/usr/bin/env bash
set -euo pipefail

source /cvhci/temp/squan/qwen_object_service/.venv/bin/activate
export HF_HOME=/cvhci/temp/squan/hf_cache
export HUGGINGFACE_HUB_CACHE=/cvhci/temp/squan/hf_cache/hub
export TRANSFORMERS_CACHE=/cvhci/temp/squan/hf_cache/transformers
export QWEN3_VL_MODEL=/cvhci/temp/squan/models/Qwen3-VL-8B-Instruct
export FORCE_QWENVL_VIDEO_READER="${FORCE_QWENVL_VIDEO_READER:-decord}"
export FINDMYTHINGS_OBJECT_HOST="${FINDMYTHINGS_OBJECT_HOST:-127.0.0.1}"
export FINDMYTHINGS_OBJECT_PORT="${FINDMYTHINGS_OBJECT_PORT:-8765}"
export FINDMYTHINGS_DATA_DIR="${FINDMYTHINGS_DATA_DIR:-/cvhci/temp/squan/qwen_object_service/data}"

if [[ -z "${CUDA_VISIBLE_DEVICES:-}" ]]; then
  echo "Set CUDA_VISIBLE_DEVICES to a safe physical GPU before starting." >&2
  exit 2
fi

exec /cvhci/temp/squan/qwen_object_service/.mamba_env/bin/python \
  /cvhci/temp/squan/qwen_object_service/api_server_phase3_fixed.py
