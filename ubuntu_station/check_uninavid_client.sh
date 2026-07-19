#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/log"
export ROS_LOG_DIR="$SCRIPT_DIR/log"
export PYTHONUNBUFFERED=1

set +u
source /opt/ros/jazzy/setup.bash
set -u

topic="/vln/uninavid/actions"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

topic_list_file="$tmp_dir/topic_list.txt"
if ! timeout 10s ros2 topic list >"$topic_list_file" 2>"$tmp_dir/topic_list.err"; then
    echo "[FAIL] unable to list ROS2 topics"
    cat "$tmp_dir/topic_list.err" >&2
    exit 1
fi

if ! grep -Fxq "$topic" "$topic_list_file"; then
    echo "[FAIL] Uni-NaVid action topic missing: $topic"
    exit 1
fi

echo "[PASS] Uni-NaVid action topic exists"

if ! timeout 30s ros2 topic echo --once "$topic"; then
    echo "[FAIL] Uni-NaVid action not received"
    exit 1
fi

echo "[PASS] Uni-NaVid action received"
echo
echo "========================="
echo "UNINAVID CLIENT PASSED"
echo "========================="
