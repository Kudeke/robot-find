import random


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
