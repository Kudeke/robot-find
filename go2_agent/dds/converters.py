def _get_attr(obj, names, default=None):
    if obj is None:
        return default
    for name in names:
        if hasattr(obj, name):
            return getattr(obj, name)
    return default


def _to_float(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _to_int(value, default=0):
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def _sequence_values(value, length, defaults):
    if value is None:
        return list(defaults)

    field_names = ("x", "y", "z", "w")
    if any(hasattr(value, field_names[index]) for index in range(min(length, 4))):
        return [
            _to_float(getattr(value, field_names[index], defaults[index]), defaults[index])
            for index in range(length)
        ]

    try:
        values = list(value)
    except TypeError:
        return list(defaults)

    result = list(defaults)
    for index in range(min(length, len(values))):
        result[index] = _to_float(values[index], defaults[index])
    return result


def _vector3(value):
    values = _sequence_values(value, 3, (0.0, 0.0, 0.0))
    return {
        "x": values[0],
        "y": values[1],
        "z": values[2],
    }


def _quaternion(imu_state):
    value = _get_attr(
        imu_state,
        ("quaternion", "quat", "orientation"),
        None,
    )
    values = _sequence_values(value, 4, (0.0, 0.0, 0.0, 1.0))
    return {
        "x": values[0],
        "y": values[1],
        "z": values[2],
        "w": values[3],
    }


def _extract_percentage(bms_state):
    if bms_state is None:
        return None

    value = _get_attr(
        bms_state,
        (
            "soc",
            "state_of_charge",
            "percentage",
            "battery_percentage",
            "battery_percent",
            "relative_soc",
        ),
        None,
    )
    if value is None:
        return None

    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def lowstate_to_battery_json(msg):
    return {
        "percentage": _extract_percentage(getattr(msg, "bms_state", None)),
        "voltage": _to_float(getattr(msg, "power_v", 0.0)),
        "current": _to_float(getattr(msg, "power_a", 0.0)),
        "temperature_ntc1": _to_int(getattr(msg, "temperature_ntc1", 0)),
        "temperature_ntc2": _to_int(getattr(msg, "temperature_ntc2", 0)),
        "tick": _to_int(getattr(msg, "tick", 0)),
    }


def lowstate_to_imu_json(msg):
    imu_state = getattr(msg, "imu_state", None)
    gyroscope = _get_attr(
        imu_state,
        ("gyroscope", "gyro", "angular_velocity"),
        None,
    )
    accelerometer = _get_attr(
        imu_state,
        ("accelerometer", "accel", "linear_acceleration"),
        None,
    )
    return {
        "orientation": _quaternion(imu_state),
        "angular_velocity": _vector3(gyroscope),
        "linear_acceleration": _vector3(accelerometer),
    }


def sportstate_to_robot_state_json(msg):
    position = _sequence_values(getattr(msg, "position", None), 3, (0.0, 0.0, 0.0))
    velocity = _sequence_values(getattr(msg, "velocity", None), 3, (0.0, 0.0, 0.0))
    foot_force_value = getattr(msg, "foot_force", None)
    try:
        foot_force = [_to_float(value) for value in list(foot_force_value)]
    except TypeError:
        foot_force = []

    return {
        "robot_mode": _to_int(getattr(msg, "mode", 0)),
        "error_code": _to_int(getattr(msg, "error_code", 0)),
        "position": position,
        "velocity": velocity,
        "yaw_speed": _to_float(getattr(msg, "yaw_speed", 0.0)),
        "foot_force": foot_force,
        "online": True,
    }


def sportstate_to_odom_json(msg):
    position = _sequence_values(getattr(msg, "position", None), 3, (0.0, 0.0, 0.0))
    velocity = _sequence_values(getattr(msg, "velocity", None), 3, (0.0, 0.0, 0.0))
    yaw_speed = _to_float(getattr(msg, "yaw_speed", 0.0))
    imu_state = getattr(msg, "imu_state", None)

    return {
        "frame_id": "odom",
        "child_frame_id": "base_link",
        "position": {
            "x": position[0],
            "y": position[1],
            "z": position[2],
        },
        "orientation": _quaternion(imu_state),
        "linear_velocity": {
            "x": velocity[0],
            "y": velocity[1],
            "z": velocity[2],
        },
        "angular_velocity": {
            "x": 0.0,
            "y": 0.0,
            "z": yaw_speed,
        },
    }
