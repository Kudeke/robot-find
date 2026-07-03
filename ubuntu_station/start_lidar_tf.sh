#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/log"
export ROS_LOG_DIR="$SCRIPT_DIR/log"

set +u
source /opt/ros/jazzy/setup.bash
set -u

echo "[HOST][LIDAR_TF] publishing temporary zero extrinsics"
echo "[HOST][LIDAR_TF] base_link -> utlidar_lidar"

exec ros2 run tf2_ros static_transform_publisher \
    0 0 0 0 0 0 base_link utlidar_lidar
