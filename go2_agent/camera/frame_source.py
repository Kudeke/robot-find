import base64
import threading

import cv2
from cv_bridge import CvBridge
from rclpy.qos import qos_profile_sensor_data
from sensor_msgs.msg import Image


class RosCameraFrameSource:
    def __init__(
        self,
        node,
        topic="/camera/camera/color/image_raw",
        camera="color",
        jpeg_quality=70,
    ):
        self._camera = str(camera)
        self._jpeg_quality = max(1, min(100, int(jpeg_quality)))
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

    def get_camera_frame(self):
        with self._lock:
            if self._latest_frame is None:
                return None
            frame = self._latest_frame.copy()

        try:
            success, encoded = cv2.imencode(
                ".jpg",
                frame,
                [cv2.IMWRITE_JPEG_QUALITY, self._jpeg_quality],
            )
        except Exception as exc:
            print(f"[GO2][CAMERA] JPEG encoding failed: {exc}")
            return None
        if not success:
            print("[GO2][CAMERA] JPEG encoding failed")
            return None

        height, width = frame.shape[:2]
        jpeg_base64 = base64.b64encode(encoded.tobytes()).decode("ascii")
        return {
            "camera": self._camera,
            "width": int(width),
            "height": int(height),
            "encoding": "jpeg",
            "jpeg_base64": jpeg_base64,
        }
