import json
import time


VERSION = 1
ROLE = "go2_agent"


def now_ns():
    return time.time_ns()


def make_heartbeat(seq, connection_id):
    message = {
        "type": "heartbeat",
        "connection_id": str(connection_id),
        "version": VERSION,
        "seq": int(seq),
        "timestamp_ns": now_ns(),
        "role": ROLE,
        "payload": {
            "status": "alive",
        },
    }
    return json.dumps(message, separators=(",", ":"))


def make_robot_state(seq, connection_id, state):
    message = {
        "type": "robot_state",
        "version": VERSION,
        "seq": int(seq),
        "timestamp_ns": now_ns(),
        "connection_id": str(connection_id),
        "payload": dict(state),
    }
    return json.dumps(message, separators=(",", ":"))


def make_odom(seq, connection_id, odom):
    message = {
        "type": "odom",
        "version": VERSION,
        "seq": int(seq),
        "timestamp_ns": now_ns(),
        "connection_id": str(connection_id),
        "payload": dict(odom),
    }
    return json.dumps(message, separators=(",", ":"))


def make_imu(seq, connection_id, imu):
    message = {
        "type": "imu",
        "version": VERSION,
        "seq": int(seq),
        "timestamp_ns": now_ns(),
        "connection_id": str(connection_id),
        "payload": dict(imu),
    }
    return json.dumps(message, separators=(",", ":"))


def make_battery(seq, connection_id, battery):
    message = {
        "type": "battery",
        "version": VERSION,
        "seq": int(seq),
        "timestamp_ns": now_ns(),
        "connection_id": str(connection_id),
        "payload": dict(battery),
    }
    return json.dumps(message, separators=(",", ":"))


def parse_message(raw):
    if isinstance(raw, bytes):
        raw = raw.decode("utf-8")
    try:
        msg = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON: {exc}") from exc
    if not isinstance(msg, dict):
        raise ValueError("message must be a JSON object")
    return msg


def validate_message(msg, expected_type=None):
    if not isinstance(msg, dict):
        raise ValueError("message must be a dict")

    required_fields = ("type", "version", "seq", "timestamp_ns", "payload")
    for field in required_fields:
        if field not in msg:
            raise ValueError(f"missing field: {field}")

    if expected_type is not None and msg["type"] != expected_type:
        raise ValueError(f"expected type {expected_type}, got {msg['type']}")

    if msg["version"] != VERSION:
        raise ValueError(f"unsupported version: {msg['version']}")

    if not isinstance(msg["seq"], int):
        raise ValueError("seq must be int")

    if not isinstance(msg["timestamp_ns"], int):
        raise ValueError("timestamp_ns must be int")

    if "role" in msg and not isinstance(msg["role"], str):
        raise ValueError("role must be str")

    if "connection_id" in msg and not isinstance(msg["connection_id"], str):
        raise ValueError("connection_id must be str")

    if not isinstance(msg["payload"], dict):
        raise ValueError("payload must be object")

    return True
