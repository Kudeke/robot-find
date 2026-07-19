#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

export MAMBA_ROOT_PREFIX="/cvhci/temp/squan/Navila/micromamba-root"
MICROMAMBA="/cvhci/temp/squan/Navila/micromamba-bin/micromamba"

eval "$("${MICROMAMBA}" shell hook --shell bash)"
micromamba activate uninavid

export TMPDIR="/cvhci/temp/squan/tmp/uninavid"
export TEMP="${TMPDIR}"
export TMP="${TMPDIR}"
export PIP_CACHE_DIR="/cvhci/temp/squan/cache/pip"
export HF_HOME="/cvhci/temp/squan/cache/huggingface"
export TORCH_HOME="/cvhci/temp/squan/cache/torch"
export CUDA_VISIBLE_DEVICES="${CUDA_VISIBLE_DEVICES:-0}"
export PYTORCH_CUDA_ALLOC_CONF="max_split_size_mb:128"

mkdir -p "${TMPDIR}" "${PIP_CACHE_DIR}" "${HF_HOME}" "${TORCH_HOME}"

python -m realtime_server.websocket_server "$@"
