#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -x "$SCRIPT_DIR/build/go2_motion_daemon" ]; then
    echo "[MOTION_DAEMON][ERROR] missing executable: $SCRIPT_DIR/build/go2_motion_daemon"
    echo "Build it first: cd $SCRIPT_DIR && ./build_helper.sh"
    exit 1
fi

GO2_MOTION_IFACE="${GO2_MOTION_IFACE:-eth0}"
GO2_MOTION_SOCKET="${GO2_MOTION_SOCKET:-/tmp/go2_motion_daemon.sock}"
GO2_MOTION_WATCHDOG_MS="${GO2_MOTION_WATCHDOG_MS:-500}"
GO2_MOTION_MAX_VX="${GO2_MOTION_MAX_VX:-0.30}"
GO2_MOTION_MAX_YAW="${GO2_MOTION_MAX_YAW:-0.30}"

if ! ip link show "$GO2_MOTION_IFACE" >/dev/null 2>&1; then
    echo "[MOTION_DAEMON][ERROR] network interface $GO2_MOTION_IFACE not found"
    exit 1
fi

echo "[MOTION_DAEMON] DEFAULT MODE: DRYRUN MOVE"
echo "[MOTION_DAEMON] Real Move requires GO2_REAL_MOVE_ACK=YES and --enable-real-move"

exec "$SCRIPT_DIR/build/go2_motion_daemon" \
    --iface "$GO2_MOTION_IFACE" \
    --socket-path "$GO2_MOTION_SOCKET" \
    --watchdog-ms "$GO2_MOTION_WATCHDOG_MS" \
    --max-vx "$GO2_MOTION_MAX_VX" \
    --max-vy 0.0 \
    --max-yaw "$GO2_MOTION_MAX_YAW" \
    "$@"
