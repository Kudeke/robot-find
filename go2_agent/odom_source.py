import math

from dds.converters import sportstate_to_odom_json


class MockOdomSource:
    def __init__(self):
        self.x = 0.0
        self.y = 0.0
        self.yaw = 0.0
        self.linear_velocity_x = 0.05
        self.angular_velocity_z = 0.05
        self.dt = 0.1

    def get_odom(self):
        self.x += self.linear_velocity_x * self.dt
        self.yaw += self.angular_velocity_z * self.dt

        half_yaw = self.yaw * 0.5
        return {
            "frame_id": "odom",
            "child_frame_id": "base_link",
            "position": {
                "x": self.x,
                "y": self.y,
                "z": 0.0,
            },
            "orientation": {
                "x": 0.0,
                "y": 0.0,
                "z": math.sin(half_yaw),
                "w": math.cos(half_yaw),
            },
            "linear_velocity": {
                "x": self.linear_velocity_x,
                "y": 0.0,
                "z": 0.0,
            },
            "angular_velocity": {
                "x": 0.0,
                "y": 0.0,
                "z": self.angular_velocity_z,
            },
        }


class RealDdsOdomSource:
    def __init__(self, node, topic="/lf/sportmodestate"):
        from rclpy.qos import qos_profile_sensor_data
        from unitree_go.msg import SportModeState

        self._latest_odom = None
        self._subscription = node.create_subscription(
            SportModeState,
            topic,
            self._on_sport_state,
            qos_profile_sensor_data,
        )

    def _on_sport_state(self, message):
        self._latest_odom = sportstate_to_odom_json(message)

    def get_odom(self):
        if self._latest_odom is None:
            return None
        return {
            "frame_id": self._latest_odom["frame_id"],
            "child_frame_id": self._latest_odom["child_frame_id"],
            "position": dict(self._latest_odom["position"]),
            "orientation": dict(self._latest_odom["orientation"]),
            "linear_velocity": dict(self._latest_odom["linear_velocity"]),
            "angular_velocity": dict(self._latest_odom["angular_velocity"]),
        }
