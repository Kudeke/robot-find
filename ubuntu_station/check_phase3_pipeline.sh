#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

mkdir -p "$SCRIPT_DIR/log"
export ROS_LOG_DIR="$SCRIPT_DIR/log"

set +u
source /opt/ros/jazzy/setup.bash
set -u

failures=0
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pass() {
    echo "[PASS] $1"
}

fail() {
    echo "[FAIL] $1"
    failures=$((failures + 1))
}

topic_list_file="$tmp_dir/topic_list.txt"
if ! timeout 10s ros2 topic list >"$topic_list_file" 2>"$tmp_dir/topic_list.err"; then
    fail "ros2 topic list"
    cat "$tmp_dir/topic_list.err" >&2
    : >"$topic_list_file"
fi

declare -a required_topics=(
    "/battery_state"
    "/remote/imu"
    "/remote/odom"
    "/go2/state"
    "/tf"
)

declare -A topic_exists
for topic in "${required_topics[@]}"; do
    if grep -Fxq "$topic" "$topic_list_file"; then
        topic_exists["$topic"]=1
    else
        topic_exists["$topic"]=0
    fi
done

declare -A websocket_topics=(
    [battery]="/battery_state"
    [imu]="/remote/imu"
    [odom]="/remote/odom"
    [robot_state]="/go2/state"
)

declare -A echo_pids
declare -A echo_files

for message_type in battery imu odom robot_state; do
    topic="${websocket_topics[$message_type]}"
    output_file="$tmp_dir/${message_type}.out"
    echo_files["$message_type"]="$output_file"

    if [ "${topic_exists[$topic]}" -eq 1 ]; then
        timeout 10s ros2 topic echo --once "$topic" >"$output_file" 2>&1 &
        echo_pids["$message_type"]=$!
    fi
done

declare -A data_ok
for message_type in battery imu odom robot_state; do
    topic="${websocket_topics[$message_type]}"
    data_ok["$message_type"]=0

    if [ "${topic_exists[$topic]}" -eq 1 ]; then
        pid="${echo_pids[$message_type]}"
        if wait "$pid"; then
            if [ -s "${echo_files[$message_type]}" ]; then
                data_ok["$message_type"]=1
            fi
        fi
    fi
done

for message_type in battery imu odom robot_state; do
    if [ "${data_ok[$message_type]}" -eq 1 ]; then
        pass "websocket $message_type"
    else
        fail "websocket $message_type"
        output_file="${echo_files[$message_type]}"
        if [ -f "$output_file" ] && [ -s "$output_file" ]; then
            cat "$output_file" >&2
        fi
    fi
done

echo

for topic in /battery_state /remote/imu /remote/odom /go2/state; do
    message_type=""
    case "$topic" in
        /battery_state) message_type="battery" ;;
        /remote/imu) message_type="imu" ;;
        /remote/odom) message_type="odom" ;;
        /go2/state) message_type="robot_state" ;;
    esac

    if [ "${topic_exists[$topic]}" -eq 1 ] && [ "${data_ok[$message_type]}" -eq 1 ]; then
        pass "topic $topic"
    else
        fail "topic $topic"
    fi
done

if [ "${topic_exists[/tf]}" -eq 1 ]; then
    pass "topic /tf"
else
    fail "topic /tf"
fi

echo

tf_output="$tmp_dir/tf.out"
timeout 10s ros2 run tf2_ros tf2_echo odom base_link >"$tf_output" 2>&1
tf_status=$?

if grep -Eq "At time|Translation:" "$tf_output"; then
    pass "tf odom->base_link"
else
    fail "tf odom->base_link"
    cat "$tf_output" >&2
    if [ "$tf_status" -ne 0 ] && [ "$tf_status" -ne 124 ]; then
        echo "[FAIL] tf2_echo exit code: $tf_status" >&2
    fi
fi

if [ "$failures" -eq 0 ]; then
    echo
    echo "========================="
    echo "PHASE3 PASSED"
    echo "========================="
    exit 0
fi

echo
echo "========================="
echo "PHASE3 FAILED ($failures)"
echo "========================="
exit 1
