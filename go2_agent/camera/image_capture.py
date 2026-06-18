import threading
from pathlib import Path

import cv2
from cv_bridge import CvBridge
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image


class RosImageCapture:
    def __init__(self, node, topic="/camera/camera/color/image_raw"):
        self._bridge = CvBridge()
        self._lock = threading.Lock()
        self._latest_frame = None
        self._subscription = node.create_subscription(
            Image,
            topic,
            self._on_image,
            qos_profile_sensor_data,
        )

    def _on_image(self, message):
        try:
            frame = self._bridge.imgmsg_to_cv2(message, desired_encoding="bgr8")
        except Exception as exc:
            print(f"[GO2][CAMERA] image conversion failed: {exc}")
            return

        with self._lock:
            self._latest_frame = frame.copy()

    def has_frame(self):
        with self._lock:
            return self._latest_frame is not None

    def get_latest_frame(self):
        with self._lock:
            if self._latest_frame is None:
                return None
            return self._latest_frame.copy()

    def save_latest_jpeg(self, output_path):
        frame = self.get_latest_frame()
        if frame is None:
            return False

        try:
            path = Path(output_path)
            path.parent.mkdir(parents=True, exist_ok=True)
            return bool(cv2.imwrite(str(path), frame))
        except Exception as exc:
            print(f"[GO2][CAMERA] JPEG save failed: {exc}")
            return False
