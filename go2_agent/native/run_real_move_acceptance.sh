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

exec "$SCRIPT_DIR/build/real_move_acceptance" --iface wlan0
