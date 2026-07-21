#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

DAEMON="$SCRIPT_DIR/build/go2_motion_daemon"
SOCKET_PATH="${GO2_MOTION_SOCKET:-/tmp/go2_motion_daemon_real_test.sock}"
LOG_FILE="$(mktemp)"
VX="${GO2_REAL_DAEMON_VX:-0.30}"
DURATION_SEC="${GO2_REAL_DAEMON_DURATION_SEC:-0.5}"

cleanup() {
    if [ -n "${DAEMON_PID:-}" ] && kill -0 "$DAEMON_PID" >/dev/null 2>&1; then
        kill "$DAEMON_PID" >/dev/null 2>&1 || true
        wait "$DAEMON_PID" >/dev/null 2>&1 || true
    fi
    rm -f "$SOCKET_PATH" "$LOG_FILE"
}
trap cleanup EXIT

if [[ "${GO2_REAL_MOVE_ACK:-}" != "YES" ]]; then
    echo "[ERROR] export GO2_REAL_MOVE_ACK=YES"
    exit 1
fi

if [ ! -x "$DAEMON" ]; then
    echo "[FAIL] daemon executable missing: $DAEMON"
    echo "Build it first: cd $SCRIPT_DIR && ./build_helper.sh"
    exit 1
fi

echo "=================================================="
echo "REAL GO2 MOTION DAEMON TEST"
echo "=================================================="
echo
echo "Robot WILL MOVE through Unix Socket daemon."
echo
echo "Expected motion:"
echo "forward"
echo "$VX m/s"
echo "$DURATION_SEC second"
echo
echo "Emergency stop must be available."
echo
echo "Type YES to continue."
echo
echo "=================================================="
read -r answer
if [ "$answer" != "YES" ]; then
    echo "[REAL DAEMON TEST] cancelled"
    exit 1
fi

"$DAEMON" \
    --iface eth0 \
    --socket-path "$SOCKET_PATH" \
    --watchdog-ms 500 \
    --max-vx 0.50 \
    --max-vy 0.0 \
    --max-yaw 0.30 \
    --enable-real-move >"$LOG_FILE" 2>&1 &
DAEMON_PID=$!

for _ in $(seq 1 160); do
    if [ -S "$SOCKET_PATH" ]; then
        break
    fi
    if ! kill -0 "$DAEMON_PID" >/dev/null 2>&1; then
        echo "[FAIL] daemon exited before socket creation"
        cat "$LOG_FILE"
        exit 1
    fi
    sleep 0.1
done

if [ ! -S "$SOCKET_PATH" ]; then
    echo "[FAIL] daemon did not create socket"
    cat "$LOG_FILE"
    exit 1
fi
echo "[PASS] daemon real mode started"

cd "$AGENT_DIR"
python3 - "$SOCKET_PATH" "$VX" "$DURATION_SEC" <<'PY'
import sys
import time

from native_motion_controller import NativeMotionController

socket_path = sys.argv[1]
vx = float(sys.argv[2])
duration_sec = float(sys.argv[3])

controller = NativeMotionController(socket_path=socket_path)
if not controller.connect():
    raise RuntimeError("cannot connect to real motion daemon")

try:
    status = controller.status()
    print(f"[PASS] status {status}")
    if not status.get("real_move_enabled", False):
        raise RuntimeError(f"daemon is not in real move mode: {status}")

    end = time.monotonic() + duration_sec
    count = 0
    while time.monotonic() < end:
        ack = controller.move(vx, 0.0, 0.0)
        if not ack.get("real_move", False):
            raise RuntimeError(f"move did not report real_move=true: {ack}")
        count += 1
        time.sleep(0.05)
    print(f"[PASS] real moves sent count={count}")

    stop_ack = controller.stop()
    print(f"[PASS] stop {stop_ack}")
finally:
    controller.close()
PY

sleep 0.3
kill "$DAEMON_PID" >/dev/null 2>&1 || true
wait "$DAEMON_PID" >/dev/null 2>&1 || true
DAEMON_PID=""

echo "[REAL DAEMON TEST] daemon log:"
cat "$LOG_FILE"

echo
echo "Robot moved and stopped as expected? [y/N]"
read -r moved_answer
case "$moved_answer" in
    y|Y|yes|YES)
        echo "[PASS] robot real daemon motion confirmed"
        ;;
    *)
        echo "[FAIL] robot motion confirmation missing"
        exit 1
        ;;
esac

echo
echo "========================="
echo "MOTION DAEMON REAL MOVE PASSED"
echo "========================="
