from dds.converters import lowstate_to_battery_json


class MockBatterySource:
    def get_battery(self):
        return {
            "percentage": 88.0,
            "voltage": 31.0,
            "current": 0.1,
            "temperature_ntc1": 40,
            "temperature_ntc2": 39,
            "tick": 0,
        }


class RealDdsBatterySource:
    def __init__(self, node, topic="/lf/lowstate"):
        from rclpy.qos import qos_profile_sensor_data
        from unitree_go.msg import LowState

        self._latest_battery = None
        self._subscription = node.create_subscription(
            LowState,
            topic,
            self._on_lowstate,
            qos_profile_sensor_data,
        )

    def _on_lowstate(self, message):
        self._latest_battery = lowstate_to_battery_json(message)

    def get_battery(self):
        if self._latest_battery is None:
            return None
        return dict(self._latest_battery)
