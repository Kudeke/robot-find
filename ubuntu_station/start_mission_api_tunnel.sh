#!/usr/bin/env bash
set -euo pipefail

SERVER_USER="${UNINAVID_SERVER_USER:-squan}"
SERVER_HOST="${UNINAVID_SERVER_HOST:-i14s42}"
LOCAL_PORT="${MISSION_API_LOCAL_PORT:-18765}"
REMOTE_PORT="${MISSION_API_REMOTE_PORT:-8765}"

usage() {
    echo "Usage: $0 [--server-user USER] [--server-host HOST]"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --server-user) SERVER_USER="$2"; shift 2 ;;
        --server-host) SERVER_HOST="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 2 ;;
    esac
done

echo "[TUNNEL] Mission API localhost:${LOCAL_PORT} -> server 127.0.0.1:${REMOTE_PORT}"
exec ssh -N -L "${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}" "${SERVER_USER}@${SERVER_HOST}"
