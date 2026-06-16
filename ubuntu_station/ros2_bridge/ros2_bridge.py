import rclpy
from rclpy.node import Node

from ros2_bridge.go2_state_publisher import Go2StatePublisher
from ros2_bridge.odom_tf_publisher import OdomTfPublisher


class Ros2Bridge:
    def __init__(self):
        rclpy.init(args=None)
        self.node = Node("go2_ros2_bridge")
        self.state_publisher = Go2StatePublisher(self.node)
        self.odom_tf_publisher = OdomTfPublisher(self.node)

    def publish_state(self, payload):
        self.state_publisher.publish_state(payload)
        rclpy.spin_once(self.node, timeout_sec=0.0)

    def publish_odom(self, payload):
        self.odom_tf_publisher.publish_odom(payload)
        rclpy.spin_once(self.node, timeout_sec=0.0)

    def close(self):
        self.node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
