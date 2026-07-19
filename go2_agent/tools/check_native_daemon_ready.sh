#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SOCKET_PATH="${NATIVE_MOTION_SOCKET:-/tmp/go2_motion_daemon.sock}"

if [ ! -S "$SOCKET_PATH" ]; then
    echo "[FAIL] motion daemon socket missing: $SOCKET_PATH"
    exit 1
fi
echo "[PASS] motion daemon socket"

if ! pgrep -f '(^|/)go2_motion_daemon([[:space:]]|$)' >/dev/null 2>&1; then
    echo "[FAIL] motion daemon process missing: go2_motion_daemon"
    exit 1
fi
echo "[PASS] motion daemon process"

cd "$AGENT_DIR"

python3 - "$SOCKET_PATH" <<'PY'
import sys

from native_motion_controller import NativeMotionController

socket_path = sys.argv[1]
controller = NativeMotionController(socket_path=socket_path)

try:
    if not controller.connect():
        print("[FAIL] daemon status unavailable")
        raise SystemExit(1)

    status = controller.status()
    if status.get("type") != "status" or not status.get("connected", False):
        print(f"[FAIL] daemon status invalid: {status}")
        raise SystemExit(1)
    print("[PASS] motion daemon status")

    if bool(status.get("real_move_enabled", False)):
        print("[FAIL] daemon real move is enabled")
        raise SystemExit(1)
    print("[PASS] real_move_enabled=false")
finally:
    controller.close()
PY

echo
echo "========================="
echo "NATIVE DAEMON READY"
echo "========================="
