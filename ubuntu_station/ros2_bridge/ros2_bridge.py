import base64
import json
import math
import threading

from camera_bridge import CameraBridge
from geometry_msgs.msg import TransformStamped, Twist
from nav_msgs.msg import Odometry
import rclpy
from rclpy.executors import ExternalShutdownException, SingleThreadedExecutor
from rclpy.node import Node
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import BatteryState, Imu, PointCloud2, PointField
from std_msgs.msg import String
from tf2_ros import TransformBroadcaster


class Ros2Bridge:
    def __init__(self):
        rclpy.init(args=None)
        self.node = Node("go2_bridge")
        self.cmd_vel_callback = None
        self.state_publisher = self.node.create_publisher(String, "/go2/state", 10)
        self.odom_publisher = self.node.create_publisher(Odometry, "/remote/odom", 10)
        self.imu_publisher = self.node.create_publisher(Imu, "/remote/imu", 10)
        self.battery_publisher = self.node.create_publisher(
            BatteryState,
            "/battery_state",
            10,
        )
        self.lidar_publisher = self.node.create_publisher(
            PointCloud2,
            "/remote/lidar/points",
            qos_profile_sensor_data,
        )
        self.camera_bridge = CameraBridge(self.node)
        self.tf_broadcaster = TransformBroadcaster(self.node)
        self.cmd_vel_subscription = self.node.create_subscription(
            Twist,
            "/cmd_vel",
            self._on_cmd_vel,
            10,
        )
        self.executor = SingleThreadedExecutor()
        self.executor.add_node(self.node)
        self.spin_thread = threading.Thread(target=self._spin, daemon=True)
        self.spin_thread.start()

    def set_cmd_vel_callback(self, callback):
        self.cmd_vel_callback = callback

    def _spin(self):
        try:
            self.executor.spin()
        except ExternalShutdownException:
            pass

    def publish_state(self, payload):
        msg = String()
        msg.data = json.dumps(payload, separators=(",", ":"))
        self.state_publisher.publish(msg)

    def publish_odom(self, payload):
        frame_id = str(payload.get("frame_id", "odom"))
        child_frame_id = str(payload.get("child_frame_id", "base_link"))
        position = payload.get("position", {})
        orientation = payload.get("orientation", {})
        linear_velocity = payload.get("linear_velocity", {})
        angular_velocity = payload.get("angular_velocity", {})
        stamp = self.node.get_clock().now().to_msg()

        odom_msg = Odometry()
        odom_msg.header.stamp = stamp
        odom_msg.header.frame_id = frame_id
        odom_msg.child_frame_id = child_frame_id
        odom_msg.pose.pose.position.x = float(position.get("x", 0.0))
        odom_msg.pose.pose.position.y = float(position.get("y", 0.0))
        odom_msg.pose.pose.position.z = float(position.get("z", 0.0))
        odom_msg.pose.pose.orientation.x = float(orientation.get("x", 0.0))
        odom_msg.pose.pose.orientation.y = float(orientation.get("y", 0.0))
        odom_msg.pose.pose.orientation.z = float(orientation.get("z", 0.0))
        odom_msg.pose.pose.orientation.w = float(orientation.get("w", 1.0))
        odom_msg.twist.twist.linear.x = float(linear_velocity.get("x", 0.0))
        odom_msg.twist.twist.linear.y = float(linear_velocity.get("y", 0.0))
        odom_msg.twist.twist.linear.z = float(linear_velocity.get("z", 0.0))
        odom_msg.twist.twist.angular.x = float(angular_velocity.get("x", 0.0))
        odom_msg.twist.twist.angular.y = float(angular_velocity.get("y", 0.0))
        odom_msg.twist.twist.angular.z = float(angular_velocity.get("z", 0.0))
        self.odom_publisher.publish(odom_msg)

        transform = TransformStamped()
        transform.header.stamp = stamp
        transform.header.frame_id = frame_id
        transform.child_frame_id = child_frame_id
        transform.transform.translation.x = odom_msg.pose.pose.position.x
        transform.transform.translation.y = odom_msg.pose.pose.position.y
        transform.transform.translation.z = odom_msg.pose.pose.position.z
        transform.transform.rotation = odom_msg.pose.pose.orientation
        self.tf_broadcaster.sendTransform(transform)

    def publish_imu(self, payload):
        orientation = payload.get("orientation", {})
        angular_velocity = payload.get("angular_velocity", {})
        linear_acceleration = payload.get("linear_acceleration", {})
        stamp = self.node.get_clock().now().to_msg()

        msg = Imu()
        msg.header.stamp = stamp
        msg.header.frame_id = "base_link"
        msg.orientation.x = float(orientation.get("x", 0.0))
        msg.orientation.y = float(orientation.get("y", 0.0))
        msg.orientation.z = float(orientation.get("z", 0.0))
        msg.orientation.w = float(orientation.get("w", 1.0))
        msg.angular_velocity.x = float(angular_velocity.get("x", 0.0))
        msg.angular_velocity.y = float(angular_velocity.get("y", 0.0))
        msg.angular_velocity.z = float(angular_velocity.get("z", 0.0))
        msg.linear_acceleration.x = float(linear_acceleration.get("x", 0.0))
        msg.linear_acceleration.y = float(linear_acceleration.get("y", 0.0))
        msg.linear_acceleration.z = float(linear_acceleration.get("z", 0.0))
        self.imu_publisher.publish(msg)

    def publish_battery(self, payload):
        percentage = payload.get("percentage")
        temperature = payload.get("temperature_ntc1")

        msg = BatteryState()
        msg.header.stamp = self.node.get_clock().now().to_msg()
        msg.header.frame_id = "base_link"
        msg.voltage = float(payload.get("voltage", math.nan))
        msg.current = float(payload.get("current", math.nan))
        if percentage is None:
            msg.percentage = math.nan
        else:
            percentage_value = float(percentage)
            msg.percentage = (
                percentage_value / 100.0
                if percentage_value > 1.0
                else percentage_value
            )
        msg.temperature = (
            float(temperature)
            if temperature is not None
            else math.nan
        )
        msg.power_supply_status = BatteryState.POWER_SUPPLY_STATUS_UNKNOWN
        self.battery_publisher.publish(msg)

    def publish_camera_jpeg(self, jpeg_bytes, camera="color"):
        self.camera_bridge.publish_jpeg(jpeg_bytes, camera=camera)

    def publish_lidar_points(self, payload):
        stamp = payload.get("stamp", {})
        fields = payload.get("fields", [])
        data_base64 = payload.get("data_base64")

        if not isinstance(stamp, dict):
            raise ValueError("lidar stamp must be an object")
        if not isinstance(fields, list):
            raise ValueError("lidar fields must be a list")
        if not isinstance(data_base64, str):
            raise ValueError("lidar data_base64 must be a string")

        try:
            data = base64.b64decode(data_base64, validate=True)
        except Exception as exc:
            raise ValueError(f"invalid lidar data_base64: {exc}") from exc

        msg = PointCloud2()
        msg.header.frame_id = str(payload.get("frame_id", ""))
        msg.header.stamp.sec = int(stamp.get("sec", 0))
        msg.header.stamp.nanosec = int(stamp.get("nanosec", 0))
        msg.height = int(payload.get("height", 0))
        msg.width = int(payload.get("width", 0))
        msg.fields = []

        for field_payload in fields:
            if not isinstance(field_payload, dict):
                raise ValueError("lidar field must be an object")
            field = PointField()
            field.name = str(field_payload.get("name", ""))
            field.offset = int(field_payload.get("offset", 0))
            field.datatype = int(field_payload.get("datatype", 0))
            field.count = int(field_payload.get("count", 0))
            msg.fields.append(field)

        msg.is_bigendian = bool(payload.get("is_bigendian", False))
        msg.point_step = int(payload.get("point_step", 0))
        msg.row_step = int(payload.get("row_step", 0))
        msg.data = data
        msg.is_dense = bool(payload.get("is_dense", False))
        self.lidar_publisher.publish(msg)
        return len(data)

    def _on_cmd_vel(self, msg):
        print(
            "[HOST][ROS2] recv /cmd_vel "
            f"linear_x={msg.linear.x} "
            f"linear_y={msg.linear.y} "
            f"angular_z={msg.angular.z}"
        )
        callback = self.cmd_vel_callback
        if callback is None:
            return
        callback(
            {
                "linear_x": msg.linear.x,
                "linear_y": msg.linear.y,
                "angular_z": msg.angular.z,
            }
        )

    def close(self):
        self.executor.shutdown()
        self.spin_thread.join(timeout=1.0)
        self.node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
