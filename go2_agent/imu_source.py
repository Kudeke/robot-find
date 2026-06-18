import math

from dds.converters import lowstate_to_imu_json


class MockImuSource:
    def __init__(self):
        self.yaw = 0.0
        self.angular_velocity_z = 0.05
        self.dt = 0.1

    def get_imu(self):
        self.yaw += self.angular_velocity_z * self.dt
        half_yaw = self.yaw * 0.5

        return {
            "orientation": {
                "x": 0.0,
                "y": 0.0,
                "z": math.sin(half_yaw),
                "w": math.cos(half_yaw),
            },
            "angular_velocity": {
                "x": 0.0,
                "y": 0.0,
                "z": self.angular_velocity_z,
            },
            "linear_acceleration": {
                "x": 0.0,
                "y": 0.0,
                "z": 9.81,
            },
        }


class RealDdsImuSource:
    def __init__(self, node, topic="/lf/lowstate"):
        from rclpy.qos import qos_profile_sensor_data
        from unitree_go.msg import LowState

        self._latest_imu = None
        self._subscription = node.create_subscription(
            LowState,
            topic,
            self._on_lowstate,
            qos_profile_sensor_data,
        )

    def _on_lowstate(self, message):
        self._latest_imu = lowstate_to_imu_json(message)

    def get_imu(self):
        if self._latest_imu is None:
            return None
        return {
            "orientation": dict(self._latest_imu["orientation"]),
            "angular_velocity": dict(self._latest_imu["angular_velocity"]),
            "linear_acceleration": dict(self._latest_imu["linear_acceleration"]),
        }
