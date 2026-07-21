#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VX="${GO2_MANUAL_REAL_VX:-0.30}"
YAW="${GO2_MANUAL_REAL_YAW:-0.0}"
DURATION_SEC="${GO2_MANUAL_REAL_DURATION_SEC:-2.0}"
RATE_HZ="${GO2_MANUAL_REAL_RATE_HZ:-10}"

python3 - "$VX" "$YAW" "$DURATION_SEC" "$RATE_HZ" <<'PY'
import sys

vx = float(sys.argv[1])
yaw = float(sys.argv[2])
duration = float(sys.argv[3])
rate = float(sys.argv[4])

if abs(vx) > 0.50:
    raise SystemExit("[ERROR] GO2_MANUAL_REAL_VX must be <= 0.50")
if abs(yaw) > 0.30:
    raise SystemExit("[ERROR] GO2_MANUAL_REAL_YAW must be <= 0.30")
if duration <= 0.0 or duration > 7.0:
    raise SystemExit("[ERROR] GO2_MANUAL_REAL_DURATION_SEC must be > 0 and <= 7")
if rate <= 0.0 or rate > 20.0:
    raise SystemExit("[ERROR] GO2_MANUAL_REAL_RATE_HZ must be > 0 and <= 20")
PY

set +u
source /opt/ros/jazzy/setup.bash
set -u

stop_cmd() {
    ros2 topic pub --once /cmd_vel geometry_msgs/msg/Twist \
        "{linear: {x: 0.0, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: 0.0}}" \
        >/dev/null 2>&1 || true
}

trap stop_cmd EXIT INT TERM

echo "=================================================="
echo "MANUAL /cmd_vel REAL MOVE TEST"
echo "=================================================="
echo
echo "Robot WILL MOVE through:"
echo "Ubuntu /cmd_vel -> WebSocket -> GO2 Agent -> Native daemon"
echo
echo "This test does NOT use Uni-NaVid or Action Translator."
echo
echo "Expected command:"
echo "linear.x=$VX m/s"
echo "angular.z=$YAW rad/s"
echo "duration=$DURATION_SEC second"
echo "rate=$RATE_HZ Hz"
echo
echo "Emergency stop must be available."
echo
echo "Type YES to continue."
echo
echo "=================================================="
read -r answer
if [ "$answer" != "YES" ]; then
    echo "[MANUAL REAL TEST] cancelled"
    exit 1
fi

echo "[MANUAL REAL TEST] sending /cmd_vel"
timeout "$DURATION_SEC" ros2 topic pub -r "$RATE_HZ" /cmd_vel geometry_msgs/msg/Twist \
    "{linear: {x: $VX, y: 0.0, z: 0.0}, angular: {x: 0.0, y: 0.0, z: $YAW}}" || true

echo "[MANUAL REAL TEST] sending stop"
stop_cmd

echo
echo "Robot moved and stopped as expected? [y/N]"
read -r moved_answer
case "$moved_answer" in
    y|Y|yes|YES)
        echo "[PASS] manual /cmd_vel real motion confirmed"
        ;;
    *)
        echo "[FAIL] robot motion confirmation missing"
        exit 1
        ;;
esac

echo
echo "========================="
echo "MANUAL CMD_VEL REAL MOVE PASSED"
echo "========================="
