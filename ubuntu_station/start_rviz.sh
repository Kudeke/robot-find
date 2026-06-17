#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

set +u
source /opt/ros/jazzy/setup.bash
set -u

exec rviz2 -d rviz/go2_phase1_mock.rviz
