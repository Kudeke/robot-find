import asyncio

import websockets

from protocol import make_cmd_vel, make_heartbeat_ack, parse_message, validate_message


class WebSocketServer:
    def __init__(self, config, ros2_bridge=None):
        self.host = config.get("host", "0.0.0.0")
        self.port = int(config.get("port", 8765))
        self.path = config.get("path", "/go2")
        self.cmd_vel_duration_ms = int(config.get("cmd_vel_duration_ms", 100))
        self.ros2_bridge = ros2_bridge
        self.server = None
        self.loop = None
        self.current_websocket = None
        self.message_counter = 0
        self.host_seq = 0

    async def run_forever(self):
        try:
            self.loop = asyncio.get_running_loop()
            self.server = await websockets.serve(
                self._handler,
                self.host,
                self.port,
                ping_interval=None,
                ping_timeout=None,
            )
            print(f"[HOST] listening on ws://{self.host}:{self.port}{self.path}")
            await asyncio.Future()
        except asyncio.CancelledError:
            raise
        finally:
            await self.close()

    async def _handler(self, websocket, path=None):
        request_path = self._get_request_path(websocket, path)
        remote_ip = self._get_remote_ip(websocket)

        if request_path != self.path:
            print(f"[HOST] rejected path {request_path} from {remote_ip}")
            await websocket.close(code=1008, reason="invalid path")
            return

        self.current_websocket = websocket
        try:
            async for raw in websocket:
                self.message_counter += 1
                try:
                    msg = parse_message(raw)
                    msg_type = msg.get("type")
                    if msg_type == "heartbeat":
                        await self._handle_heartbeat(websocket, remote_ip, msg)
                    elif msg_type == "robot_state":
                        self._handle_robot_state(remote_ip, msg)
                    elif msg_type == "odom":
                        self._handle_odom(remote_ip, msg)
                    elif msg_type == "imu":
                        self._handle_imu(remote_ip, msg)
                    else:
                        raise ValueError(f"unsupported message type: {msg_type}")
                except Exception as exc:
                    print(f"[HOST] invalid message from {remote_ip}: {exc}")
        except websockets.exceptions.ConnectionClosed:
            pass
        except Exception as exc:
            print(f"[HOST] connection error from {remote_ip}: {exc}")
        finally:
            if self.current_websocket is websocket:
                self.current_websocket = None
            print("[HOST] go2 disconnected")

    async def _handle_heartbeat(self, websocket, remote_ip, msg):
        validate_message(msg, expected_type="heartbeat")
        seq = msg["seq"]
        timestamp_ns = msg["timestamp_ns"]
        connection_id = msg.get("connection_id", "unknown")
        print(
            f"[HOST] heartbeat from {remote_ip} "
            f"seq={seq} timestamp_ns={timestamp_ns} "
            f"connection_id={connection_id} "
            f"total_messages={self.message_counter}"
        )
        await websocket.send(make_heartbeat_ack(seq))

    def _handle_robot_state(self, remote_ip, msg):
        validate_message(msg, expected_type="robot_state")
        seq = msg["seq"]
        timestamp_ns = msg["timestamp_ns"]
        connection_id = msg.get("connection_id", "unknown")
        payload = msg["payload"]
        if self.ros2_bridge is not None:
            self.ros2_bridge.publish_state(payload)
        print(
            f"[HOST] robot_state from {remote_ip} "
            f"seq={seq} timestamp_ns={timestamp_ns} "
            f"connection_id={connection_id} "
            f"total_messages={self.message_counter}"
        )

    def _handle_odom(self, remote_ip, msg):
        validate_message(msg, expected_type="odom")
        seq = msg["seq"]
        payload = msg["payload"]
        if self.ros2_bridge is not None:
            self.ros2_bridge.publish_odom(payload)
        print(
            f"[HOST] odom from {remote_ip} "
            f"seq={seq} "
            f"total_messages={self.message_counter}"
        )

    def _handle_imu(self, remote_ip, msg):
        validate_message(msg, expected_type="imu")
        seq = msg["seq"]
        payload = msg["payload"]
        if self.ros2_bridge is not None:
            self.ros2_bridge.publish_imu(payload)
        print(
            f"[HOST] imu from {remote_ip} "
            f"seq={seq} "
            f"total_messages={self.message_counter}"
        )

    def send_cmd_vel(self, cmd_dict):
        print(
            "[HOST] cmd_vel callback received "
            f"linear_x={cmd_dict.get('linear_x', 0.0)} "
            f"linear_y={cmd_dict.get('linear_y', 0.0)} "
            f"angular_z={cmd_dict.get('angular_z', 0.0)}"
        )
        websocket = self.current_websocket
        loop = self.loop
        if websocket is None or loop is None:
            print("[HOST] no active GO2 session, drop cmd_vel")
            return
        asyncio.run_coroutine_threadsafe(
            self._send_cmd_vel(websocket, cmd_dict),
            loop,
        )

    async def _send_cmd_vel(self, websocket, cmd_dict):
        if websocket is not self.current_websocket:
            print("[HOST] no active GO2 session, drop cmd_vel")
            return

        self.host_seq += 1
        seq = self.host_seq
        linear_x = float(cmd_dict.get("linear_x", 0.0))
        linear_y = float(cmd_dict.get("linear_y", 0.0))
        angular_z = float(cmd_dict.get("angular_z", 0.0))
        message = make_cmd_vel(
            seq,
            linear_x,
            linear_y,
            angular_z,
            duration_ms=self.cmd_vel_duration_ms,
        )
        try:
            await websocket.send(message)
        except websockets.exceptions.ConnectionClosed:
            print("[HOST] no active GO2 session, drop cmd_vel")
            return

        print(
            f"[HOST] send cmd_vel seq={seq} "
            f"linear_x={linear_x} linear_y={linear_y} angular_z={angular_z}"
        )

    def _get_request_path(self, websocket, path):
        if path is not None:
            return path
        if hasattr(websocket, "path"):
            return websocket.path
        request = getattr(websocket, "request", None)
        if request is not None and hasattr(request, "path"):
            return request.path
        return None

    def _get_remote_ip(self, websocket):
        remote_address = getattr(websocket, "remote_address", None)
        if isinstance(remote_address, tuple) and remote_address:
            return str(remote_address[0])
        return "unknown"

    async def close(self):
        server = self.server
        self.server = None
        if server is not None:
            server.close()
            await server.wait_closed()
