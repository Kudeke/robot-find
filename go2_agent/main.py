import asyncio
import sys

import yaml

from battery_source import MockBatterySource, RealDdsBatterySource
from imu_source import MockImuSource, RealDdsImuSource
from odom_source import MockOdomSource, RealDdsOdomSource
from state_source import MockStateSource, RealDdsRobotStateSource
from ws_client import WebSocketClient


def load_config(path="config.yaml"):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


async def async_main():
    config = load_config()
    battery_mode = str(config.get("battery_source", "mock"))
    imu_mode = str(config.get("imu_source", "mock"))
    odom_mode = str(config.get("odom_source", "mock"))
    state_mode = str(config.get("state_source", "mock"))
    camera_enabled = bool(config.get("camera_enabled", False))
    dds_node = None
    owns_rclpy = False
    client = None

    try:
        if (
            battery_mode == "real_dds"
            or imu_mode == "real_dds"
            or odom_mode == "real_dds"
            or state_mode == "real_dds"
            or camera_enabled
        ):
            import rclpy

            rclpy.init(args=None)
            owns_rclpy = True
            dds_node = rclpy.create_node("go2_dds_sources")

        if battery_mode == "real_dds":
            battery_source = RealDdsBatterySource(
                dds_node,
                topic=config.get("battery_topic", "/lf/lowstate"),
            )
            print("[GO2] battery source=real_dds")
        elif battery_mode == "mock":
            battery_source = MockBatterySource()
            print("[GO2] battery source=mock")
        else:
            raise ValueError(f"unsupported battery_source: {battery_mode}")

        if imu_mode == "real_dds":
            imu_source = RealDdsImuSource(
                dds_node,
                topic=config.get("imu_topic", "/lf/lowstate"),
            )
            print("[GO2] imu source=real_dds")
        elif imu_mode == "mock":
            imu_source = MockImuSource()
            print("[GO2] imu source=mock")
        else:
            raise ValueError(f"unsupported imu_source: {imu_mode}")

        if odom_mode == "real_dds":
            odom_source = RealDdsOdomSource(
                dds_node,
                topic=config.get("odom_topic", "/lf/sportmodestate"),
            )
            print("[GO2] odom source=real_dds")
        elif odom_mode == "mock":
            odom_source = MockOdomSource()
            print("[GO2] odom source=mock")
        else:
            raise ValueError(f"unsupported odom_source: {odom_mode}")

        if state_mode == "real_dds":
            state_source = RealDdsRobotStateSource(
                dds_node,
                topic=config.get("state_topic", "/lf/sportmodestate"),
            )
            print("[GO2] state source=real_dds")
        elif state_mode == "mock":
            state_source = MockStateSource()
            print("[GO2] state source=mock")
        else:
            raise ValueError(f"unsupported state_source: {state_mode}")

        camera_source = None
        if camera_enabled:
            from camera.frame_source import RosCameraFrameSource

            camera_source = RosCameraFrameSource(
                dds_node,
                topic=config.get(
                    "camera_topic",
                    "/camera/camera/color/image_raw",
                ),
                camera="color",
                jpeg_quality=config.get("camera_jpeg_quality", 70),
            )
            print("[GO2] camera source=color JPEG")

        client = WebSocketClient(
            config,
            battery_source=battery_source,
            imu_source=imu_source,
            odom_source=odom_source,
            state_source=state_source,
            camera_source=camera_source,
            dds_node=dds_node,
        )
        await client.run_forever()
    finally:
        if client is not None:
            await client.close()
        if dds_node is not None:
            dds_node.destroy_node()
        if owns_rclpy:
            import rclpy

            if rclpy.ok():
                rclpy.shutdown()


def main():
    try:
        asyncio.run(async_main())
    except KeyboardInterrupt:
        print("[GO2] shutdown requested")
    except Exception as exc:
        print(f"[GO2] fatal error: {exc}", file=sys.stderr)


if __name__ == "__main__":
    main()
