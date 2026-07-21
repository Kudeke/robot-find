#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "${GO2_REAL_MOVE_ACK:-}" != "YES" ]]; then
    echo "[ERROR] export GO2_REAL_MOVE_ACK=YES"
    exit 1
fi

if [ ! -x "$SCRIPT_DIR/build/real_move_acceptance" ]; then
    echo "[ERROR] missing executable: $SCRIPT_DIR/build/real_move_acceptance"
    echo "先运行 build_helper.sh"
    exit 1
fi

GO2_REAL_MOVE_IFACE="${GO2_REAL_MOVE_IFACE:-eth0}"
GO2_REAL_MOVE_VX="${GO2_REAL_MOVE_VX:-0.30}"
GO2_REAL_MOVE_DURATION_SEC="${GO2_REAL_MOVE_DURATION_SEC:-0.5}"

exec "$SCRIPT_DIR/build/real_move_acceptance" \
    --iface "$GO2_REAL_MOVE_IFACE" \
    --vx "$GO2_REAL_MOVE_VX" \
    --duration-sec "$GO2_REAL_MOVE_DURATION_SEC"
