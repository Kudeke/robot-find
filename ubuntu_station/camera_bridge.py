from sensor_msgs.msg import CompressedImage


class CameraBridge:
    def __init__(self, node):
        self._node = node
        self._publisher = node.create_publisher(
            CompressedImage,
            "/remote/camera/color/compressed",
            10,
        )

    def publish_jpeg(self, jpeg_bytes, camera="color"):
        if camera != "color":
            raise ValueError(f"unsupported camera: {camera}")

        msg = CompressedImage()
        msg.header.stamp = self._node.get_clock().now().to_msg()
        msg.header.frame_id = "camera_color_optical_frame"
        msg.format = "jpeg"
        msg.data = jpeg_bytes
        self._publisher.publish(msg)
