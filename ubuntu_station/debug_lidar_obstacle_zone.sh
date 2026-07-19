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

python3 - "$@" <<'PY'
import argparse
import math
import time

import rclpy
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import PointCloud2
from sensor_msgs_py import point_cloud2


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", default="/remote/lidar/points")
    parser.add_argument("--obstacle-x-min", type=float, default=0.15)
    parser.add_argument("--obstacle-x-max", type=float, default=0.8)
    parser.add_argument("--obstacle-half-width", type=float, default=0.35)
    parser.add_argument("--obstacle-z-min", type=float, default=-0.25)
    parser.add_argument("--obstacle-z-max", type=float, default=0.5)
    parser.add_argument("--sample-limit", type=int, default=30)
    parser.add_argument("--timeout-sec", type=float, default=5.0)
    return parser.parse_args()


def extract_xyz(point):
    try:
        return float(point["x"]), float(point["y"]), float(point["z"])
    except Exception:
        return float(point[0]), float(point[1]), float(point[2])


def main():
    args = parse_args()
    rclpy.init()
    node = rclpy.create_node("debug_lidar_obstacle_zone")
    result = {"msg": None}

    def callback(msg):
        result["msg"] = msg

    node.create_subscription(PointCloud2, args.topic, callback, qos_profile_sensor_data)

    deadline = time.time() + args.timeout_sec
    while rclpy.ok() and result["msg"] is None and time.time() < deadline:
        rclpy.spin_once(node, timeout_sec=0.1)

    msg = result["msg"]
    if msg is None:
        print(f"[FAIL] no PointCloud2 received from {args.topic}")
        node.destroy_node()
        rclpy.shutdown()
        raise SystemExit(1)

    total = 0
    in_zone = []
    nan_count = 0
    min_x = min_y = min_z = math.inf
    max_x = max_y = max_z = -math.inf

    points = point_cloud2.read_points(
        msg,
        field_names=("x", "y", "z"),
        skip_nans=False,
    )
    for point in points:
        total += 1
        x, y, z = extract_xyz(point)
        if math.isnan(x) or math.isnan(y) or math.isnan(z):
            nan_count += 1
            continue
        min_x, max_x = min(min_x, x), max(max_x, x)
        min_y, max_y = min(min_y, y), max(max_y, y)
        min_z, max_z = min(min_z, z), max(max_z, z)
        if (
            args.obstacle_x_min <= x <= args.obstacle_x_max
            and abs(y) <= args.obstacle_half_width
            and args.obstacle_z_min <= z <= args.obstacle_z_max
        ):
            if len(in_zone) < args.sample_limit:
                in_zone.append((x, y, z))
            else:
                in_zone.append(None)

    zone_count = len(in_zone)
    if None in in_zone:
        zone_count = sum(
            1
            for point in point_cloud2.read_points(
                msg,
                field_names=("x", "y", "z"),
                skip_nans=True,
            )
            if (
                args.obstacle_x_min <= extract_xyz(point)[0] <= args.obstacle_x_max
                and abs(extract_xyz(point)[1]) <= args.obstacle_half_width
                and args.obstacle_z_min <= extract_xyz(point)[2] <= args.obstacle_z_max
            )
        )
        in_zone = [p for p in in_zone if p is not None]

    print(f"topic={args.topic}")
    print(f"frame_id={msg.header.frame_id}")
    print(f"height={msg.height} width={msg.width}")
    print(f"point_count_total={total}")
    print(f"nan_count={nan_count}")
    print(f"cloud_bounds x=[{min_x:.3f}, {max_x:.3f}] y=[{min_y:.3f}, {max_y:.3f}] z=[{min_z:.3f}, {max_z:.3f}]")
    print(
        "zone="
        f"x=[{args.obstacle_x_min}, {args.obstacle_x_max}] "
        f"abs(y)<={args.obstacle_half_width} "
        f"z=[{args.obstacle_z_min}, {args.obstacle_z_max}]"
    )
    print(f"obstacle_zone_count={zone_count}")
    print("obstacle_zone_samples:")
    for x, y, z in in_zone[: args.sample_limit]:
        print(f"  x={x:.3f} y={y:.3f} z={z:.3f}")

    node.destroy_node()
    rclpy.shutdown()


if __name__ == "__main__":
    main()
PY
