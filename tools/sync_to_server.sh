#!/usr/bin/env bash
set -euo pipefail

SERVER_USER="${UNINAVID_SERVER_USER:-squan}"
SERVER_HOST="${UNINAVID_SERVER_HOST:-i14s42}"
SERVER_PATH="/cvhci/temp/squan/uninavid/"
REMOTE_TARGET="${SERVER_USER}@${SERVER_HOST}:${SERVER_PATH}"

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

UPLOAD_ENTRIES=(
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

for entry in "${UPLOAD_ENTRIES[@]}"; do
    if [[ ! -e "${PROJECT_ROOT}/${entry}" ]]; then
        echo "Required upload entry is missing: ${PROJECT_ROOT}/${entry}"
        exit 1
    fi
done

CONTROL_DIR="$(mktemp -d)"
SSH_CONTROL_PATH="${CONTROL_DIR}/ssh_control"
DRY_RUN_LOG="${CONTROL_DIR}/dry_run.log"

cleanup() {
    ssh -S "${SSH_CONTROL_PATH}" -O exit "${SERVER_USER}@${SERVER_HOST}" >/dev/null 2>&1 || true
    rm -rf "${CONTROL_DIR}"
}
trap cleanup EXIT

if ! ssh -M -S "${SSH_CONTROL_PATH}" -fN "${SERVER_USER}@${SERVER_HOST}"; then
    echo "Cannot connect to server."
    exit 1
fi

RSYNC_SSH="ssh -S ${SSH_CONTROL_PATH}"
RSYNC_SOURCES=()
for entry in "${UPLOAD_ENTRIES[@]}"; do
    RSYNC_SOURCES+=("${PROJECT_ROOT}/./${entry}")
done

echo "[SYNC] local Uni-NaVid source: ${PROJECT_ROOT}"
echo "[SYNC] remote target: ${REMOTE_TARGET}"
echo "[SYNC] files to upload:"

rsync -avhn \
    --relative \
    --out-format='%n' \
    -e "${RSYNC_SSH}" \
    "${RSYNC_EXCLUDES[@]}" \
    "${RSYNC_SOURCES[@]}" \
    "${REMOTE_TARGET}" | tee "${DRY_RUN_LOG}"

if grep -E "${FORBIDDEN_RE}" "${DRY_RUN_LOG}" >/dev/null; then
    echo "[ERROR] Forbidden path detected in upload preview. Aborting."
    grep -E "${FORBIDDEN_RE}" "${DRY_RUN_LOG}" || true
    exit 1
fi

if [[ "${APPLY}" -ne 1 ]]; then
    echo "[SYNC] Dry-run only. Re-run with --apply to upload."
    exit 0
fi

rsync -avh --progress \
    --relative \
    -e "${RSYNC_SSH}" \
    "${RSYNC_EXCLUDES[@]}" \
    "${RSYNC_SOURCES[@]}" \
    "${REMOTE_TARGET}"

echo "[PASS] Sync completed."
