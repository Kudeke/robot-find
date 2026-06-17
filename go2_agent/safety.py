class SafetyLimiter:
    def __init__(self, max_vx=0.5, max_vy=0.3, max_yaw_rate=0.8):
        self.max_vx = float(max_vx)
        self.max_vy = float(max_vy)
        self.max_yaw_rate = float(max_yaw_rate)

    def limit_cmd(self, vx, vy, yaw_rate):
        original = (float(vx), float(vy), float(yaw_rate))
        limited = (
            self._clamp(original[0], -self.max_vx, self.max_vx),
            self._clamp(original[1], -self.max_vy, self.max_vy),
            self._clamp(original[2], -self.max_yaw_rate, self.max_yaw_rate),
        )

        if limited != original:
            print(
                "[GO2][SAFETY] velocity limited from "
                f"vx={original[0]} vy={original[1]} yaw_rate={original[2]} "
                "to "
                f"vx={limited[0]} vy={limited[1]} yaw_rate={limited[2]}"
            )

        return limited

    def is_zero_cmd(self, vx, vy, yaw_rate, eps=1e-6):
        return (
            abs(float(vx)) <= eps
            and abs(float(vy)) <= eps
            and abs(float(yaw_rate)) <= eps
        )

    def _clamp(self, value, min_value, max_value):
        return max(min_value, min(max_value, value))
