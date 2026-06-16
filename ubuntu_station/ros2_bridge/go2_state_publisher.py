import json

import rclpy
from rclpy.node import Node
from std_msgs.msg import String


class Go2StatePublisher:
    def __init__(self):
        rclpy.init(args=None)
        self.node = Node("go2_state_publisher")
        self.publisher = self.node.create_publisher(String, "/go2/state", 10)

    def publish_state(self, state):
        msg = String()
        msg.data = json.dumps(state, separators=(",", ":"))
        self.publisher.publish(msg)
        rclpy.spin_once(self.node, timeout_sec=0.0)

    def close(self):
        self.node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()
