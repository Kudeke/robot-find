#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$SCRIPT_DIR/log"
export ROS_LOG_DIR="$SCRIPT_DIR/log"

set +u
source /opt/ros/jazzy/setup.bash
set -u

exec ros2 topic echo /remote/odom nav_msgs/msg/Odometry
