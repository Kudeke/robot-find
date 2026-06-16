import asyncio
import sys

import yaml

from ros2_bridge.go2_state_publisher import Go2StatePublisher
from ws_server import WebSocketServer


def load_config(path="config.yaml"):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


async def async_main():
    config = load_config()
    state_publisher = Go2StatePublisher()
    server = WebSocketServer(config, state_publisher=state_publisher)
    try:
        await server.run_forever()
    finally:
        await server.close()
        state_publisher.close()


def main():
    try:
        asyncio.run(async_main())
    except KeyboardInterrupt:
        print("[HOST] shutdown requested")
    except Exception as exc:
        print(f"[HOST] fatal error: {exc}", file=sys.stderr)


if __name__ == "__main__":
    main()
