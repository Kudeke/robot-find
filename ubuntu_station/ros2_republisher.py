"""Optional ROS2 republisher for remote GO2 observations."""

from __future__ import annotations

from typing import Any

import numpy as np

try:
    import rclpy
    from builtin_interfaces.msg import Time
    from geometry_msgs.msg import TransformStamped
    from nav_msgs.msg import Odometry
    from rclpy.qos import HistoryPolicy, QoSProfile, ReliabilityPolicy
    from sensor_msgs.msg import CompressedImage, Image
    from tf2_ros import TransformBroadcaster

    RCLPY_AVAILABLE = True
except ImportError:
    rclpy = None
    Time = None
    TransformStamped = None
    Odometry = None
    QoSProfile = None
    ReliabilityPolicy = None
    HistoryPolicy = None
    CompressedImage = None
    Image = None
    TransformBroadcaster = None
    RCLPY_AVAILABLE = False


class ROS2Republisher:
    def __init__(self, enabled: bool = True) -> None:
        self.enabled = bool(enabled and RCLPY_AVAILABLE)
        self.node = None
        self.image_pub = None
        self.compressed_pub = None
        self.odom_pub = None
        self.tf_broadcaster = None

        if not self.enabled:
            if enabled and not RCLPY_AVAILABLE:
                print("rclpy is not available; ROS2 publishing disabled")
            return

        if not rclpy.ok():
            rclpy.init(args=None)

        image_qos = QoSProfile(
            reliability=ReliabilityPolicy.BEST_EFFORT,
            history=HistoryPolicy.KEEP_LAST,
            depth=1,
        )
        reliable_qos = QoSProfile(
            reliability=ReliabilityPolicy.RELIABLE,
            history=HistoryPolicy.KEEP_LAST,
            depth=10,
        )

        self.node = rclpy.create_node("ubuntu_station_republisher")
        self.image_pub = self.node.create_publisher(Image, "/remote/image_raw", image_qos)
        self.compressed_pub = self.node.create_publisher(
            CompressedImage, "/remote/image_compressed", image_qos
        )
        self.odom_pub = self.node.create_publisher(Odometry, "/remote/odom", reliable_qos)
        self.tf_broadcaster = TransformBroadcaster(self.node, qos=reliable_qos)

    def publish(self, stamp: float, frame_bgr: np.ndarray, jpeg_bytes: bytes, state: dict[str, Any]) -> None:
        if not self.enabled:
            return

        ros_stamp = self._to_ros_time(stamp)
        self.image_pub.publish(self._make_image_msg(ros_stamp, frame_bgr))
        self.compressed_pub.publish(self._make_compressed_msg(ros_stamp, jpeg_bytes))

        odom = self._make_odom_msg(ros_stamp, state)
        self.odom_pub.publish(odom)
        self.tf_broadcaster.sendTransform(self._make_tf_msg(ros_stamp, odom))
        rclpy.spin_once(self.node, timeout_sec=0.0)

    def close(self) -> None:
        if self.node is not None:
            self.node.destroy_node()
            self.node = None
        if self.enabled and rclpy.ok():
            rclpy.shutdown()

    def _to_ros_time(self, stamp: float) -> Any:
        sec = int(stamp)
        nanosec = int((stamp - sec) * 1_000_000_000)
        return Time(sec=sec, nanosec=nanosec)

    def _make_image_msg(self, stamp: Any, frame_bgr: np.ndarray) -> Any:
        height, width = frame_bgr.shape[:2]
        msg = Image()
        msg.header.stamp = stamp
        msg.header.frame_id = "base_link"
        msg.height = height
        msg.width = width
        msg.encoding = "bgr8"
        msg.is_bigendian = False
        msg.step = width * 3
        msg.data = frame_bgr.tobytes()
        return msg

    def _make_compressed_msg(self, stamp: Any, jpeg_bytes: bytes) -> Any:
        msg = CompressedImage()
        msg.header.stamp = stamp
        msg.header.frame_id = "base_link"
        msg.format = "jpeg"
        msg.data = jpeg_bytes
        return msg

    def _make_odom_msg(self, stamp: Any, state: dict[str, Any]) -> Any:
        odom = Odometry()
        odom.header.stamp = stamp
        odom.header.frame_id = "odom"
        odom.child_frame_id = "base_link"

        pose = state.get("pose", {}) if isinstance(state.get("pose", {}), dict) else {}
        position = pose.get("position", {}) if isinstance(pose.get("position", {}), dict) else {}
        orientation = pose.get("orientation", {}) if isinstance(pose.get("orientation", {}), dict) else {}
        twist = state.get("twist", {}) if isinstance(state.get("twist", {}), dict) else {}
        linear = twist.get("linear", {}) if isinstance(twist.get("linear", {}), dict) else {}
        angular = twist.get("angular", {}) if isinstance(twist.get("angular", {}), dict) else {}

        odom.pose.pose.position.x = float(position.get("x", state.get("x", 0.0)))
        odom.pose.pose.position.y = float(position.get("y", state.get("y", 0.0)))
        odom.pose.pose.position.z = float(position.get("z", state.get("z", 0.0)))
        odom.pose.pose.orientation.x = float(orientation.get("x", state.get("qx", 0.0)))
        odom.pose.pose.orientation.y = float(orientation.get("y", state.get("qy", 0.0)))
        odom.pose.pose.orientation.z = float(orientation.get("z", state.get("qz", 0.0)))
        odom.pose.pose.orientation.w = float(orientation.get("w", state.get("qw", 1.0)))

        odom.twist.twist.linear.x = float(linear.get("x", state.get("vx", 0.0)))
        odom.twist.twist.linear.y = float(linear.get("y", state.get("vy", 0.0)))
        odom.twist.twist.linear.z = float(linear.get("z", state.get("vz", 0.0)))
        odom.twist.twist.angular.x = float(angular.get("x", state.get("wx", 0.0)))
        odom.twist.twist.angular.y = float(angular.get("y", state.get("wy", 0.0)))
        odom.twist.twist.angular.z = float(angular.get("z", state.get("yaw_rate", state.get("wz", 0.0))))
        return odom

    def _make_tf_msg(self, stamp: Any, odom: Any) -> Any:
        tf_msg = TransformStamped()
        tf_msg.header.stamp = stamp
        tf_msg.header.frame_id = "odom"
        tf_msg.child_frame_id = "base_link"
        tf_msg.transform.translation.x = odom.pose.pose.position.x
        tf_msg.transform.translation.y = odom.pose.pose.position.y
        tf_msg.transform.translation.z = odom.pose.pose.position.z
        tf_msg.transform.rotation = odom.pose.pose.orientation
        return tf_msg
