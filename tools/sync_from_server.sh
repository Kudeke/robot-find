#!/usr/bin/env bash

set -euo pipefail

SERVER_USER="squan"
SERVER_HOST="cvhci_42server"
SERVER_PATH="/cvhci/temp/squan/uninavid/"
LOCAL_PATH="$HOME/go2_uninavid/"

if ! command -v rsync >/dev/null 2>&1; then
    echo "rsync is not installed."
    exit 1
fi

if ! ssh "${SERVER_USER}@${SERVER_HOST}" "echo ok" >/dev/null; then
    echo "Cannot connect to server."
    exit 1
fi

rsync -avh --progress \
    --exclude='model_zoo/' \
    --exclude='output/' \
    --exclude='test_cases/' \
    --exclude='hf_download/' \
    --exclude='**pycache**/' \
    --exclude='.git/' \
    --exclude='*.pyc' \
    --exclude='*.pyo' \
    "${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}" "${LOCAL_PATH}"

echo "[PASS] Sync completed."
