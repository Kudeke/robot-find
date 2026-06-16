import json

import rclpy
from std_msgs.msg import String


class Go2StatePublisher:
    def __init__(self, node):
        self.node = node
        self.publisher = self.node.create_publisher(String, "/go2/state", 10)

    def publish_state(self, state):
        msg = String()
        msg.data = json.dumps(state, separators=(",", ":"))
        self.publisher.publish(msg)
