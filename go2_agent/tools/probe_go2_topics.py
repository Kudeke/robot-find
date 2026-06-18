#!/usr/bin/env python3
import os
import shutil
import subprocess


TOPICS = [
    "/lf/sportmodestate",
    "/sportmodestate",
    "/lowstate",
    "/lf/lowstate",
    "/odom",
    "/imu",
    "/battery_state",
    "/joint_states",
]

SETUP_FILES = [
    "/opt/ros/foxy/setup.bash",
    "/opt/mybotshop/setup.bash",
]


def build_source_prefix():
    commands = []
    for setup_file in SETUP_FILES:
        if os.path.isfile(setup_file):
            commands.append(f"source {setup_file}")
    return "; ".join(commands)


def run_ros2(args, timeout_sec=5):
    source_prefix = build_source_prefix()
    ros2_command = " ".join(args)
    if source_prefix:
        command = f"{source_prefix}; {ros2_command}"
    else:
        command = ros2_command

    return subprocess.run(
        ["bash", "-lc", command],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout_sec,
        check=False,
    )


def print_limited_lines(text, max_lines=80):
    lines = text.splitlines()
    for line in lines[:max_lines]:
        print(line)
    if len(lines) > max_lines:
        print(f"[GO2][DDS_PROBE] ... truncated {len(lines) - max_lines} lines")


def get_topic_types():
    result = run_ros2(["ros2", "topic", "list", "-t"])
    topic_types = {}
    if result.returncode != 0:
        print("[GO2][DDS_PROBE] failed to list topics")
        if result.stderr:
            print(result.stderr.rstrip())
        return topic_types

    for line in result.stdout.splitlines():
        stripped = line.strip()
        if not stripped or " [" not in stripped or not stripped.endswith("]"):
            continue
        topic, type_part = stripped.split(" [", 1)
        topic_types[topic] = type_part[:-1]
    return topic_types


def probe_topic(topic, topic_type):
    print(f"[GO2][DDS_PROBE] topic={topic}")
    print(f"[GO2][DDS_PROBE] type={topic_type}")

    info_result = run_ros2(["ros2", "topic", "info", topic])
    print("[GO2][DDS_PROBE] ros2 topic info:")
    if info_result.stdout:
        print(info_result.stdout.rstrip())
    if info_result.stderr:
        print(info_result.stderr.rstrip())

    echo_result = run_ros2(["timeout", "3s", "ros2", "topic", "echo", "--once", topic], timeout_sec=5)
    print("[GO2][DDS_PROBE] ros2 topic echo --once first 80 lines:")
    if echo_result.stdout:
        print_limited_lines(echo_result.stdout, max_lines=80)
    if echo_result.stderr:
        print(echo_result.stderr.rstrip())
    print(f"[GO2][DDS_PROBE] echo_returncode={echo_result.returncode}")


def main():
    print("[GO2][DDS_PROBE] GO2 local DDS/ROS2 topic probe")
    print("[GO2][DDS_PROBE] safe mode: ros2 CLI read-only, no control commands")
    print("[GO2][DDS_PROBE] DDS is local to GO2; WiFi bridge remains WebSocket JSON only")

    if shutil.which("bash") is None:
        print("[GO2][DDS_PROBE] missing bash")
        return

    topic_types = get_topic_types()
    if not topic_types:
        print("[GO2][DDS_PROBE] no topics discovered")

    for topic in TOPICS:
        topic_type = topic_types.get(topic)
        if topic_type is None:
            print(f"[GO2][DDS_PROBE] topic={topic} missing")
            continue
        probe_topic(topic, topic_type)


if __name__ == "__main__":
    main()
