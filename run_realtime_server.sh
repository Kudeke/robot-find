#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

export MAMBA_ROOT_PREFIX="${SCRIPT_DIR}/.micromamba"
MICROMAMBA="${SCRIPT_DIR}/.micromamba-bin/micromamba"

if [[ ! -x "${MICROMAMBA}" ]]; then
  echo "[ERROR] micromamba not found: ${MICROMAMBA}"
  exit 1
fi

eval "$("${MICROMAMBA}" shell hook --shell bash)"
micromamba activate uninavid
export LD_LIBRARY_PATH="${CONDA_PREFIX}/lib/python3.10/site-packages/nvidia/cuda_runtime/lib:${CONDA_PREFIX}/lib/python3.10/site-packages/nvidia/cusparse/lib:${CONDA_PREFIX}/lib/python3.10/site-packages/nvidia/cublas/lib:${CONDA_PREFIX}/lib/python3.10/site-packages/torch/lib:${LD_LIBRARY_PATH:-}"

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
