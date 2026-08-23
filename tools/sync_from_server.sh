#!/usr/bin/env bash
set -euo pipefail

SERVER_USER="${UNINAVID_SERVER_USER:-squan}"
SERVER_HOST="${UNINAVID_SERVER_HOST:-i14s42}"
SERVER_PATH="/cvhci/temp/squan/robotfind_uninavid/"
REMOTE_SOURCE="${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}"

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
    APPLY=1
    shift
fi
if [[ $# -ne 0 ]]; then
    echo "Usage: $0 [--apply]"
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if ! command -v rsync >/dev/null 2>&1; then
    echo "rsync is not installed."
    exit 1
fi

find_uninavid_root() {
    local -a roots=()

    if [[ -f "${WORKSPACE_ROOT}/pyproject.toml" \
        && -f "${WORKSPACE_ROOT}/offline_eval_uninavid.py" \
        && -f "${WORKSPACE_ROOT}/uninavid/__init__.py" ]]; then
        roots+=("${WORKSPACE_ROOT}")
    fi

    while IFS= read -r candidate; do
        if [[ -f "${candidate}/pyproject.toml" \
            && -f "${candidate}/offline_eval_uninavid.py" \
            && -f "${candidate}/uninavid/__init__.py" ]]; then
            roots+=("${candidate}")
        fi
    done < <(find "${WORKSPACE_ROOT}" -mindepth 1 -maxdepth 3 -type d 2>/dev/null | sort)

    mapfile -t roots < <(printf '%s\n' "${roots[@]}" | awk '!seen[$0]++')

    if [[ "${#roots[@]}" -ne 1 ]]; then
        echo "Cannot uniquely locate Uni-NaVid source root."
        printf 'Candidates found:\n'
        printf '  %s\n' "${roots[@]:-<none>}"
        exit 1
    fi

    printf '%s\n' "${roots[0]}"
}

PROJECT_ROOT="$(find_uninavid_root)"

DOWNLOAD_ENTRIES=(
    "realtime_server"
    "run_realtime_server.sh"
    "run_realtime_test.sh"
    "pyproject.toml"
)

RSYNC_EXCLUDES=(
    --exclude='ubuntu_station/'
    --exclude='go2_agent/'
    --exclude='rviz/'
    --exclude='ros2_bridge/'
    --exclude='docs/'
    --exclude='log/'
    --exclude='logs/'
    --exclude='captures/'
    --exclude='model_zoo/'
    --exclude='test_cases/'
    --exclude='output/'
    --exclude='hf_download/'
    --exclude='cache/'
    --exclude='tmp/'
    --exclude='.git/'
    --exclude='**/__pycache__/'
    --exclude='**pycache**/'
    --exclude='*.pyc'
    --exclude='*.pyo'
    --exclude='*.log'
)

FORBIDDEN_RE='(^|[[:space:]/])(ubuntu_station|go2_agent|model_zoo|test_cases|output|\.git)(/|$)'

if ! ssh "${SERVER_USER}@${SERVER_HOST}" "echo ok" >/dev/null; then
    echo "Cannot connect to server."
    exit 1
fi

DRY_RUN_LOG="$(mktemp)"
cleanup() {
    rm -f "${DRY_RUN_LOG}"
}
trap cleanup EXIT

echo "[SYNC] remote Uni-NaVid source: ${REMOTE_SOURCE}"
echo "[SYNC] local target: ${PROJECT_ROOT}"
echo "[SYNC] files to download:"

for entry in "${DOWNLOAD_ENTRIES[@]}"; do
    rsync -avhn \
        --out-format='%n' \
        "${RSYNC_EXCLUDES[@]}" \
        "${REMOTE_SOURCE}${entry}" \
        "${PROJECT_ROOT}/" | tee -a "${DRY_RUN_LOG}"
done

if grep -E "${FORBIDDEN_RE}" "${DRY_RUN_LOG}" >/dev/null; then
    echo "[ERROR] Forbidden path detected in download preview. Aborting."
    grep -E "${FORBIDDEN_RE}" "${DRY_RUN_LOG}" || true
    exit 1
fi

if [[ "${APPLY}" -ne 1 ]]; then
    echo "[SYNC] Dry-run only. Re-run with --apply to download."
    exit 0
fi

for entry in "${DOWNLOAD_ENTRIES[@]}"; do
    rsync -avh --progress \
        "${RSYNC_EXCLUDES[@]}" \
        "${REMOTE_SOURCE}${entry}" \
        "${PROJECT_ROOT}/"
done

echo "[PASS] Sync completed."
