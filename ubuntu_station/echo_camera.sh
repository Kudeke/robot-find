#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/jazzy/setup.bash
set -u

topic="/remote/camera/color/compressed"

echo "[HOST][CAMERA] topic info"
ros2 topic info "$topic"

echo "[HOST][CAMERA] message rate"
ros2 topic hz "$topic"
