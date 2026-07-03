import base64
import threading


class RealDdsPointCloudSource:
    def __init__(self, node, topic="/utlidar/cloud"):
        from rclpy.qos import qos_profile_sensor_data
        from sensor_msgs.msg import PointCloud2

        self._lock = threading.Lock()
        self._latest_pointcloud = None
        self._subscription = node.create_subscription(
            PointCloud2,
            topic,
            self._on_pointcloud,
            qos_profile_sensor_data,
        )

    def _on_pointcloud(self, message):
        with self._lock:
            self._latest_pointcloud = message

    def get_pointcloud_json(self):
        with self._lock:
            message = self._latest_pointcloud
            if message is None:
                return None

            frame_id = str(message.header.frame_id)
            stamp_sec = int(message.header.stamp.sec)
            stamp_nanosec = int(message.header.stamp.nanosec)
            height = int(message.height)
            width = int(message.width)
            fields = [
                {
                    "name": str(field.name),
                    "offset": int(field.offset),
                    "datatype": int(field.datatype),
                    "count": int(field.count),
                }
                for field in message.fields
            ]
            is_bigendian = bool(message.is_bigendian)
            point_step = int(message.point_step)
            row_step = int(message.row_step)
            is_dense = bool(message.is_dense)
            data = bytes(message.data)

        return {
            "frame_id": frame_id,
            "stamp": {
                "sec": stamp_sec,
                "nanosec": stamp_nanosec,
            },
            "height": height,
            "width": width,
            "fields": fields,
            "is_bigendian": is_bigendian,
            "point_step": point_step,
            "row_step": row_step,
            "is_dense": is_dense,
            "data_base64": base64.b64encode(data).decode("ascii"),
        }
