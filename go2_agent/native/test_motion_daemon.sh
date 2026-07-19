#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DAEMON="$SCRIPT_DIR/build/go2_motion_daemon"
SOCKET_PATH="/tmp/go2_motion_daemon_test.sock"
LOG_FILE="$(mktemp)"

cleanup() {
    if [ -n "${DAEMON_PID:-}" ] && kill -0 "$DAEMON_PID" >/dev/null 2>&1; then
        kill "$DAEMON_PID" >/dev/null 2>&1 || true
        wait "$DAEMON_PID" >/dev/null 2>&1 || true
    fi
    rm -f "$SOCKET_PATH" "$LOG_FILE"
}
trap cleanup EXIT

if [ ! -x "$DAEMON" ]; then
    echo "[FAIL] daemon executable missing: $DAEMON"
    exit 1
fi

"$DAEMON" \
    --iface wlan0 \
    --socket-path "$SOCKET_PATH" \
    --watchdog-ms 500 \
    --max-vx 0.15 \
    --max-vy 0.0 \
    --max-yaw 0.30 >"$LOG_FILE" 2>&1 &
DAEMON_PID=$!

for _ in $(seq 1 50); do
    if [ -S "$SOCKET_PATH" ]; then
        break
    fi
    sleep 0.1
done

if [ ! -S "$SOCKET_PATH" ]; then
    echo "[FAIL] daemon did not create socket"
    cat "$LOG_FILE"
    exit 1
fi
echo "[PASS] daemon started"

python3 - "$SOCKET_PATH" <<'PY'
import json
import socket
import sys
import time

path = sys.argv[1]

def send(sock, payload):
    sock.sendall((json.dumps(payload, separators=(",", ":")) + "\n").encode())
    return json.loads(sock.recv(4096).decode().strip())

sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
sock.connect(path)

assert send(sock, {"type": "ping"})["type"] == "pong"
print("[PASS] ping")

move_ack = send(sock, {"type": "move", "seq": 1, "vx": 0.05, "vy": 0.0, "yaw": 0.0})
assert move_ack["type"] == "move_ack" and move_ack["accepted"] is True
assert move_ack["real_move"] is False
print("[PASS] dryrun move")

status = send(sock, {"type": "status"})
assert status["type"] == "status"

time.sleep(0.8)
stop_ack = send(sock, {"type": "stop", "seq": 2})
assert stop_ack["type"] == "stop_ack"
print("[PASS] explicit stop")

sock.close()
PY

sleep 0.2
if ! grep -q "\[MOTION_DAEMON\]\[DRYRUN\] move seq=1" "$LOG_FILE"; then
    echo "[FAIL] dryrun move log missing"
    cat "$LOG_FILE"
    exit 1
fi
if ! grep -q "\[MOTION_DAEMON\]\[WATCHDOG\] command timeout, StopMove" "$LOG_FILE"; then
    echo "[FAIL] watchdog log missing"
    cat "$LOG_FILE"
    exit 1
fi
echo "[PASS] watchdog stop"

if ! grep -q "\[MOTION_DAEMON\] stop seq=2" "$LOG_FILE"; then
    echo "[FAIL] explicit stop log missing"
    cat "$LOG_FILE"
    exit 1
fi

if ! grep -q "client disconnected, StopMove" "$LOG_FILE"; then
    echo "[FAIL] disconnect stop log missing"
    cat "$LOG_FILE"
    exit 1
fi
echo "[PASS] disconnect stop"

kill "$DAEMON_PID" >/dev/null 2>&1 || true
wait "$DAEMON_PID" >/dev/null 2>&1 || true
DAEMON_PID=""

if [ -S "$SOCKET_PATH" ]; then
    echo "[FAIL] socket cleanup"
    cat "$LOG_FILE"
    exit 1
fi

echo "[PASS] socket cleanup"
echo
echo "========================="
echo "MOTION DAEMON DRYRUN PASSED"
echo "========================="
