import asyncio
import time
import uuid

import websockets

from controller import DryRunController, SafeController
from imu_source import MockImuSource
from native_stop_controller import NativeStopController
from odom_source import MockOdomSource
from protocol import (
    make_battery,
    make_camera_frame,
    make_heartbeat,
    make_imu,
    make_lidar_points,
    make_odom,
    make_robot_state,
    parse_message,
    validate_message,
)
from safety import SafetyLimiter
from state_source import MockStateSource


class WebSocketClient:
    def __init__(
        self,
        config,
        battery_source=None,
        imu_source=None,
        odom_source=None,
        state_source=None,
        camera_source=None,
        lidar_source=None,
        dds_node=None,
    ):
        self.server_url = config.get("server_url", "ws://192.168.41.1:8765/go2")
        self.heartbeat_interval_sec = float(config.get("heartbeat_interval_sec", 1.0))
        self.reconnect_interval_sec = float(config.get("reconnect_interval_sec", 2.0))
        self.websocket = None
        self.seq = 0
        self.connection_id = uuid.uuid4().hex
        self.state_source = state_source if state_source is not None else MockStateSource()
        self.odom_source = odom_source if odom_source is not None else MockOdomSource()
        self.imu_source = imu_source if imu_source is not None else MockImuSource()
        self.battery_source = battery_source
        self.camera_source = camera_source
        self.lidar_source = lidar_source
        self.dds_node = dds_node
        self.safety_limiter = SafetyLimiter(
            max_vx=config.get("max_vx", 0.5),
            max_vy=config.get("max_vy", 0.3),
            max_yaw_rate=config.get("max_yaw_rate", 0.8),
        )
        native_stop_controller = None
        if config.get("native_stop_enabled", True):
            native_stop_controller = NativeStopController(
                helper_path=config.get("native_stop_helper_path", "./native/build/go2_sport_helper"),
                network_interface=config.get("native_stop_interface", "wlan0"),
                enabled=config.get("native_stop_enabled", True),
                timeout_sec=config.get("native_stop_timeout_sec", 5.0),
            )
        self.controller = SafeController(
            dry_run_controller=DryRunController(dry_run=config.get("dry_run", True)),
            native_stop_controller=native_stop_controller,
        )
        self.command_timeout_sec = float(config.get("command_timeout_sec", 0.5))
        self.last_cmd_time = None
        self.last_motion_command = None
        self.stop_sent = False
        state_rate_hz = float(config.get("state_rate_hz", 1.0))
        if state_rate_hz <= 0.0:
            raise ValueError("state_rate_hz must be greater than 0")
        self.robot_state_interval_sec = 1.0 / state_rate_hz
        odom_rate_hz = float(config.get("odom_rate_hz", 10.0))
        if odom_rate_hz <= 0.0:
            raise ValueError("odom_rate_hz must be greater than 0")
        self.odom_interval_sec = 1.0 / odom_rate_hz
        imu_rate_hz = float(config.get("imu_rate_hz", 10.0))
        if imu_rate_hz <= 0.0:
            raise ValueError("imu_rate_hz must be greater than 0")
        self.imu_interval_sec = 1.0 / imu_rate_hz
        battery_rate_hz = float(config.get("battery_rate_hz", 1.0))
        if battery_rate_hz <= 0.0:
            raise ValueError("battery_rate_hz must be greater than 0")
        self.battery_interval_sec = 1.0 / battery_rate_hz
        camera_rate_hz = float(config.get("camera_rate_hz", 1.0))
        if camera_rate_hz <= 0.0:
            raise ValueError("camera_rate_hz must be greater than 0")
        self.camera_interval_sec = 1.0 / camera_rate_hz
        lidar_rate_hz = float(config.get("lidar_rate_hz", 5.0))
        if lidar_rate_hz <= 0.0:
            raise ValueError("lidar_rate_hz must be greater than 0")
        self.lidar_interval_sec = 1.0 / lidar_rate_hz
        self._stopping = False

    async def run_forever(self):
        while not self._stopping:
            try:
                print(f"[GO2] connecting to {self.server_url}")
                async with websockets.connect(self.server_url) as websocket:
                    self.websocket = websocket
                    print("[GO2] connected")
                    await self._run_connected(websocket)
            except asyncio.CancelledError:
                self._stopping = True
                raise
            except KeyboardInterrupt:
                self._stopping = True
                print("[GO2][SAFETY] keyboard interrupt, stop")
                self.controller.stop()
                break
            except Exception as exc:
                print(f"[GO2] connection error: {exc}")
            finally:
                self.websocket = None

            if not self._stopping:
                print(f"[GO2] disconnected, retry in {self.reconnect_interval_sec}s")
                try:
                    await asyncio.sleep(self.reconnect_interval_sec)
                except asyncio.CancelledError:
                    self._stopping = True
                    raise

    async def _run_connected(self, websocket):
        sender = asyncio.create_task(self._heartbeat_loop(websocket))
        state_sender = asyncio.create_task(self._robot_state_loop(websocket))
        odom_sender = asyncio.create_task(self._odom_loop(websocket))
        imu_sender = asyncio.create_task(self._imu_loop(websocket))
        battery_sender = asyncio.create_task(self._battery_loop(websocket))
        camera_sender = asyncio.create_task(self._camera_loop(websocket))
        lidar_sender = asyncio.create_task(self._lidar_loop(websocket))
        dds_spinner = asyncio.create_task(self._dds_spin_loop())
        timeout_checker = asyncio.create_task(self._command_timeout_loop())
        receiver = asyncio.create_task(self._receive_loop(websocket))
        try:
            done, pending = await asyncio.wait(
                {
                    sender,
                    state_sender,
                    odom_sender,
                    imu_sender,
                    battery_sender,
                    camera_sender,
                    lidar_sender,
                    dds_spinner,
                    timeout_checker,
                    receiver,
                },
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in done:
                exc = task.exception()
                if exc:
                    raise exc
        finally:
            if self.last_cmd_time is not None:
                print("[GO2][SAFETY] websocket disconnected, stop")
                self.controller.stop()
                self.stop_sent = True

            for task in (
                sender,
                state_sender,
                odom_sender,
                imu_sender,
                battery_sender,
                camera_sender,
                lidar_sender,
                dds_spinner,
                timeout_checker,
                receiver,
            ):
                if not task.done():
                    task.cancel()
            await asyncio.gather(
                sender,
                state_sender,
                odom_sender,
                imu_sender,
                battery_sender,
                camera_sender,
                lidar_sender,
                dds_spinner,
                timeout_checker,
                receiver,
                return_exceptions=True,
            )

    def _next_seq(self):
        self.seq += 1
        return self.seq

    async def _heartbeat_loop(self, websocket):
        while not self._stopping:
            seq = self._next_seq()
            message = make_heartbeat(seq, self.connection_id)
            await websocket.send(message)
            print(f"[GO2] send heartbeat seq={seq}")
            await asyncio.sleep(self.heartbeat_interval_sec)

    async def _robot_state_loop(self, websocket):
        while not self._stopping:
            state = self.state_source.get_state()
            if state is not None:
                seq = self._next_seq()
                message = make_robot_state(seq, self.connection_id, state)
                await websocket.send(message)
                print(f"[GO2] send robot_state seq={seq}")
            await asyncio.sleep(self.robot_state_interval_sec)

    async def _odom_loop(self, websocket):
        while not self._stopping:
            odom = self.odom_source.get_odom()
            if odom is not None:
                seq = self._next_seq()
                message = make_odom(seq, self.connection_id, odom)
                await websocket.send(message)
                print(f"[GO2] send odom seq={seq}")
            await asyncio.sleep(self.odom_interval_sec)

    async def _imu_loop(self, websocket):
        while not self._stopping:
            imu = self.imu_source.get_imu()
            if imu is not None:
                seq = self._next_seq()
                message = make_imu(seq, self.connection_id, imu)
                await websocket.send(message)
                print(f"[GO2] send imu seq={seq}")
            await asyncio.sleep(self.imu_interval_sec)

    async def _battery_loop(self, websocket):
        while not self._stopping:
            if self.battery_source is not None:
                battery = self.battery_source.get_battery()
                if battery is not None:
                    seq = self._next_seq()
                    message = make_battery(seq, self.connection_id, battery)
                    await websocket.send(message)
                    print(
                        f"[GO2] send battery seq={seq} "
                        f"percentage={battery.get('percentage')} "
                        f"voltage={battery.get('voltage')}"
                    )
            await asyncio.sleep(self.battery_interval_sec)

    async def _camera_loop(self, websocket):
        while not self._stopping:
            if self.camera_source is not None:
                frame = self.camera_source.get_camera_frame()
                if frame is not None:
                    seq = self._next_seq()
                    message = make_camera_frame(seq, self.connection_id, frame)
                    await websocket.send(message)
                    print(
                        f"[GO2] send camera_frame seq={seq} "
                        f"camera={frame.get('camera')} "
                        f"width={frame.get('width')} "
                        f"height={frame.get('height')}"
                    )
            await asyncio.sleep(self.camera_interval_sec)

    async def _lidar_loop(self, websocket):
        while not self._stopping:
            if self.lidar_source is not None:
                pointcloud = self.lidar_source.get_pointcloud_json()
                if pointcloud is not None:
                    seq = self._next_seq()
                    message = make_lidar_points(
                        seq,
                        self.connection_id,
                        pointcloud,
                    )
                    await websocket.send(message)
                    data_base64 = pointcloud.get("data_base64", "")
                    padding = len(data_base64) - len(data_base64.rstrip("="))
                    byte_count = len(data_base64) * 3 // 4 - padding
                    print(
                        f"[GO2] send lidar_points seq={seq} "
                        f"width={pointcloud.get('width')} "
                        f"bytes={byte_count}"
                    )
            await asyncio.sleep(self.lidar_interval_sec)

    async def _dds_spin_loop(self):
        while not self._stopping:
            if self.dds_node is not None:
                import rclpy

                rclpy.spin_once(self.dds_node, timeout_sec=0.0)
            await asyncio.sleep(0.01)

    async def _command_timeout_loop(self):
        while not self._stopping:
            if self.last_cmd_time is not None:
                elapsed = time.monotonic() - self.last_cmd_time
                if elapsed > self.command_timeout_sec and not self.stop_sent:
                    self.controller.stop()
                    self.stop_sent = True
            await asyncio.sleep(0.05)

    async def _receive_loop(self, websocket):
        async for raw in websocket:
            try:
                msg = parse_message(raw)
                msg_type = msg.get("type")
                if msg_type == "heartbeat_ack":
                    validate_message(msg, expected_type="heartbeat_ack")
                    print(f"[GO2] recv heartbeat_ack seq={msg.get('seq')}")
                elif msg_type == "cmd_vel":
                    self._handle_cmd_vel(msg)
                else:
                    raise ValueError(f"unsupported message type: {msg_type}")
            except Exception as exc:
                print(f"[GO2] invalid message ignored: {exc}")

    def _handle_cmd_vel(self, msg):
        validate_message(msg, expected_type="cmd_vel")
        print(f"[GO2] recv cmd_vel seq={msg.get('seq')}")
        self.last_cmd_time = time.monotonic()
        payload = msg["payload"]
        vx = float(payload.get("linear_x", 0.0))
        vy = float(payload.get("linear_y", 0.0))
        yaw_rate = float(payload.get("angular_z", 0.0))
        vx, vy, yaw_rate = self.safety_limiter.limit_cmd(vx, vy, yaw_rate)
        self.last_motion_command = (vx, vy, yaw_rate)
        self.stop_sent = self.safety_limiter.is_zero_cmd(vx, vy, yaw_rate)
        self.controller.move(vx, vy, yaw_rate)

    async def close(self):
        self._stopping = True
        print("[GO2][SAFETY] client closing, stop")
        self.controller.stop()
        websocket = self.websocket
        self.websocket = None
        if websocket is not None:
            try:
                await websocket.close()
            except Exception as exc:
                print(f"[GO2] close error: {exc}")
