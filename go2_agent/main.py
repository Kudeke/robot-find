import asyncio
import sys

import yaml

from battery_source import MockBatterySource, RealDdsBatterySource
from controller import DryRunController, NativeDaemonController, SafeController
from imu_source import MockImuSource, RealDdsImuSource
from native_motion_controller import NativeMotionController
from native_stop_controller import NativeStopController
from odom_source import MockOdomSource, RealDdsOdomSource
from state_source import MockStateSource, RealDdsRobotStateSource
from ws_client import WebSocketClient


def load_config(path="config.yaml"):
    with open(path, "r", encoding="utf-8") as f:
        return yaml.safe_load(f) or {}


def build_native_stop_controller(config):
    if not config.get("native_stop_enabled", True):
        return None
    return NativeStopController(
        helper_path=config.get("native_stop_helper_path", "./native/build/go2_sport_helper"),
        network_interface=config.get("native_stop_interface", "wlan0"),
        enabled=config.get("native_stop_enabled", True),
        timeout_sec=config.get("native_stop_timeout_sec", 5.0),
    )


def build_controller(config):
    controller_mode = str(config.get("controller_mode", "dry_run"))
    native_stop_controller = build_native_stop_controller(config)

    if controller_mode == "dry_run":
        print("[GO2] controller_mode=dry_run")
        return SafeController(
            dry_run_controller=DryRunController(dry_run=config.get("dry_run", True)),
            native_stop_controller=native_stop_controller,
        )

    if controller_mode == "native_daemon":
        print("[GO2] controller_mode=native_daemon")
        motion_controller = NativeMotionController(
            socket_path=config.get("native_motion_socket", "/tmp/go2_motion_daemon.sock"),
            connect_timeout_sec=config.get("native_motion_connect_timeout_sec", 2.0),
            request_timeout_sec=config.get("native_motion_request_timeout_sec", 1.0),
            fallback_stop_controller=native_stop_controller,
        )
        if not motion_controller.connect():
            raise RuntimeError("native_daemon mode requires a running motion daemon")

        status = motion_controller.status()
        print(f"[GO2][NATIVE_DAEMON] daemon status: {status}")
        if status.get("type") != "status" or not status.get("connected", False):
            raise RuntimeError(f"motion daemon status check failed: {status}")

        real_move_enabled = bool(status.get("real_move_enabled", False))
        allow_real_move_daemon = bool(config.get("allow_real_move_daemon", False))
        if real_move_enabled and not allow_real_move_daemon:
            motion_controller.close()
            raise RuntimeError(
                "motion daemon reports real_move_enabled=true, "
                "but allow_real_move_daemon=false"
            )

        return NativeDaemonController(
            motion_controller=motion_controller,
            fallback_stop_controller=native_stop_controller,
        )

    raise ValueError(f"unsupported controller_mode: {controller_mode}")


async def async_main():
    config = load_config()
    battery_mode = str(config.get("battery_source", "mock"))
    imu_mode = str(config.get("imu_source", "mock"))
    odom_mode = str(config.get("odom_source", "mock"))
    state_mode = str(config.get("state_source", "mock"))
    camera_enabled = bool(config.get("camera_enabled", False))
    lidar_enabled = bool(config.get("lidar_enabled", False))
    dds_node = None
    owns_rclpy = False
    client = None
    controller = None

    try:
        controller = build_controller(config)

        if (
            battery_mode == "real_dds"
            or imu_mode == "real_dds"
            or odom_mode == "real_dds"
            or state_mode == "real_dds"
            or camera_enabled
            or lidar_enabled
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

        lidar_source = None
        if lidar_enabled:
            from lidar_source import RealDdsPointCloudSource

            lidar_source = RealDdsPointCloudSource(
                dds_node,
                topic=config.get("lidar_topic", "/utlidar/cloud"),
            )
            print("[GO2] lidar source=real_dds PointCloud2")

        client = WebSocketClient(
            config,
            controller=controller,
            battery_source=battery_source,
            imu_source=imu_source,
            odom_source=odom_source,
            state_source=state_source,
            camera_source=camera_source,
            lidar_source=lidar_source,
            dds_node=dds_node,
        )
        await client.run_forever()
    finally:
        if client is not None:
            await client.close()
        elif controller is not None and hasattr(controller, "close"):
            controller.close()
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
        sys.exit(1)


if __name__ == "__main__":
    main()
