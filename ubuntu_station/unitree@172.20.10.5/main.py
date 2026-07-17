import asyncio
import sys

import yaml

from ws_client import WebSocketClient


def load_config(path="config.yaml"):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


async def async_main():
    config = load_config()
    client = WebSocketClient(config)
    try:
        await client.run_forever()
    finally:
        await client.close()


def main():
    try:
        asyncio.run(async_main())
    except KeyboardInterrupt:
        print("[GO2] shutdown requested")
    except Exception as exc:
        print(f"[GO2] fatal error: {exc}", file=sys.stderr)


if __name__ == "__main__":
    main()
