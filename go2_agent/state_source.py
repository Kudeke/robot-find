import random

from dds.converters import sportstate_to_robot_state_json


class MockStateSource:
    def __init__(self):
        self.battery_percent = 88.5

    def get_state(self):
        self.battery_percent = max(
            0.0,
            min(100.0, self.battery_percent + random.choice([-0.1, 0.0, 0.1])),
        )
        return {
            "robot_mode": "stand",
            "battery_percent": round(self.battery_percent, 1),
            "error_code": 0,
            "online": True,
        }


class RealDdsRobotStateSource:
    def __init__(self, node, topic="/lf/sportmodestate"):
        from rclpy.qos import qos_profile_sensor_data
        from unitree_go.msg import SportModeState

        self._latest_state = None
        self._subscription = node.create_subscription(
            SportModeState,
            topic,
            self._on_sport_state,
            qos_profile_sensor_data,
        )

    def _on_sport_state(self, message):
        self._latest_state = sportstate_to_robot_state_json(message)

    def get_state(self):
        if self._latest_state is None:
            return None
        return {
            "robot_mode": self._latest_state["robot_mode"],
            "error_code": self._latest_state["error_code"],
            "position": list(self._latest_state["position"]),
            "velocity": list(self._latest_state["velocity"]),
            "yaw_speed": self._latest_state["yaw_speed"],
            "foot_force": list(self._latest_state["foot_force"]),
            "online": self._latest_state["online"],
        }
