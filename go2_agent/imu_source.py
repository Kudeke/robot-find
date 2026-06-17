import math


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
