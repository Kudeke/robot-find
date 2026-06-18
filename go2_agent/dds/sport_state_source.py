import threading
import time

from rclpy.qos import qos_profile_sensor_data
from unitree_go.msg import SportModeState


class SportStateSource:
    def __init__(self, node, topic="/lf/sportmodestate"):
        self._node = node
        self._topic = topic
        self._lock = threading.Lock()
        self._latest_message = None
        self._last_received_monotonic = None
        self._received_count = 0
        self._subscription = node.create_subscription(
            SportModeState,
            topic,
            self._on_message,
            qos_profile_sensor_data,
        )

    @property
    def topic(self):
        return self._topic

    def _on_message(self, message):
        with self._lock:
            self._latest_message = message
            self._last_received_monotonic = time.monotonic()
            self._received_count += 1

    def has_message(self):
        with self._lock:
            return self._latest_message is not None

    def get_latest_message(self):
        with self._lock:
            return self._latest_message

    def get_status(self):
        with self._lock:
            return {
                "topic": self._topic,
                "received_count": self._received_count,
                "last_received_monotonic": self._last_received_monotonic,
                "has_message": self._latest_message is not None,
            }
