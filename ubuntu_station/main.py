import asyncio
import sys

import yaml

from ros2_bridge.ros2_bridge import Ros2Bridge
from ws_server import WebSocketServer


def load_config(path="config.yaml"):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


async def async_main():
    config = load_config()
    ros2_bridge = Ros2Bridge()
    server = WebSocketServer(config, ros2_bridge=ros2_bridge)
    ros2_bridge.set_cmd_vel_callback(server.send_cmd_vel)
    try:
        await server.run_forever()
    finally:
        ros2_bridge.close()


def main():
    try:
        asyncio.run(async_main())
    except KeyboardInterrupt:
        print("[HOST] shutdown requested")
    except Exception as exc:
        print(f"[HOST] fatal error: {exc}", file=sys.stderr)


if __name__ == "__main__":
    main()
