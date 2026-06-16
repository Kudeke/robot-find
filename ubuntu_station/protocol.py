import json
import time


VERSION = 1
ROLE = "ubuntu_station"


def now_ns():
    return time.time_ns()


def make_heartbeat_ack(seq):
    message = {
        "type": "heartbeat_ack",
        "version": VERSION,
        "seq": int(seq),
        "timestamp_ns": now_ns(),
        "role": ROLE,
        "payload": {
            "status": "ok",
        },
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
