#!/usr/bin/env bash
set -euo pipefail

set +u
source /opt/ros/jazzy/setup.bash
set -u

exec ros2 service call \
    /vln/safety_gate/set_enabled \
    std_srvs/srv/SetBool \
    "{data: false}"
