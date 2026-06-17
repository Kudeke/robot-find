import json
import threading

from geometry_msgs.msg import TransformStamped, Twist
from nav_msgs.msg import Odometry
import rclpy
from rclpy.executors import ExternalShutdownException, SingleThreadedExecutor
from rclpy.node import Node
from sensor_msgs.msg import Imu
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
