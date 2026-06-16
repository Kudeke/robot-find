import asyncio

import websockets

from protocol import make_heartbeat_ack, parse_message, validate_message


class WebSocketServer:
    def __init__(self, config, state_publisher=None):
        self.host = config.get("host", "0.0.0.0")
        self.port = int(config.get("port", 8765))
        self.path = config.get("path", "/go2")
        self.state_publisher = state_publisher
        self.server = None
        self.message_counter = 0

    async def run_forever(self):
        try:
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
                    else:
                        raise ValueError(f"unsupported message type: {msg_type}")
                except Exception as exc:
                    print(f"[HOST] invalid message from {remote_ip}: {exc}")
        except websockets.exceptions.ConnectionClosed:
            pass
        except Exception as exc:
            print(f"[HOST] connection error from {remote_ip}: {exc}")
        finally:
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
        if self.state_publisher is not None:
            self.state_publisher.publish_state(payload)
        print(
            f"[HOST] robot_state from {remote_ip} "
            f"seq={seq} timestamp_ns={timestamp_ns} "
            f"connection_id={connection_id} "
            f"total_messages={self.message_counter}"
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
