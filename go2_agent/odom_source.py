import math


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
