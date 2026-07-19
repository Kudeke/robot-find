#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -x "$SCRIPT_DIR/build/go2_motion_daemon" ]; then
    echo "[MOTION_DAEMON][ERROR] missing executable: $SCRIPT_DIR/build/go2_motion_daemon"
    echo "Build it first: cd $SCRIPT_DIR && ./build_helper.sh"
    exit 1
fi

if ! ip link show wlan0 >/dev/null 2>&1; then
    echo "[MOTION_DAEMON][ERROR] network interface wlan0 not found"
    exit 1
fi

echo "[MOTION_DAEMON] DEFAULT MODE: DRYRUN MOVE"
echo "[MOTION_DAEMON] STOP remains active"

exec "$SCRIPT_DIR/build/go2_motion_daemon" \
    --iface wlan0 \
    --socket-path /tmp/go2_motion_daemon.sock \
    --watchdog-ms 500 \
    --max-vx 0.15 \
    --max-vy 0.0 \
    --max-yaw 0.30 \
    "$@"
