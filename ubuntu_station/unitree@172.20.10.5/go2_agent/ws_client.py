import asyncio
import uuid

import websockets

from odom_source import MockOdomSource
from protocol import make_heartbeat, make_odom, make_robot_state, parse_message, validate_message
from state_source import MockStateSource


class WebSocketClient:
    def __init__(self, config):
        self.server_url = config.get("server_url", "ws://192.168.41.1:8765/go2")
        self.heartbeat_interval_sec = float(config.get("heartbeat_interval_sec", 1.0))
        self.reconnect_interval_sec = float(config.get("reconnect_interval_sec", 2.0))
        self.websocket = None
        self.seq = 0
        self.connection_id = uuid.uuid4().hex
        self.state_source = MockStateSource()
        self.odom_source = MockOdomSource()
        self.robot_state_interval_sec = 1.0
        self.odom_interval_sec = 0.1
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
        receiver = asyncio.create_task(self._receive_loop(websocket))
        try:
            done, pending = await asyncio.wait(
                {sender, state_sender, odom_sender, receiver},
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in done:
                exc = task.exception()
                if exc:
                    raise exc
        finally:
            for task in (sender, state_sender, odom_sender, receiver):
                if not task.done():
                    task.cancel()
            await asyncio.gather(
                sender,
                state_sender,
                odom_sender,
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
            seq = self._next_seq()
            state = self.state_source.get_state()
            message = make_robot_state(seq, self.connection_id, state)
            await websocket.send(message)
            print(f"[GO2] send robot_state seq={seq}")
            await asyncio.sleep(self.robot_state_interval_sec)

    async def _odom_loop(self, websocket):
        while not self._stopping:
            seq = self._next_seq()
            odom = self.odom_source.get_odom()
            message = make_odom(seq, self.connection_id, odom)
            await websocket.send(message)
            print(f"[GO2] send odom seq={seq}")
            await asyncio.sleep(self.odom_interval_sec)

    async def _receive_loop(self, websocket):
        async for raw in websocket:
            try:
                msg = parse_message(raw)
                validate_message(msg, expected_type="heartbeat_ack")
                print(f"[GO2] recv heartbeat_ack seq={msg.get('seq')}")
            except Exception as exc:
                print(f"[GO2] invalid message ignored: {exc}")

    async def close(self):
        self._stopping = True
        websocket = self.websocket
        self.websocket = None
        if websocket is not None:
            try:
                await websocket.close()
            except Exception as exc:
                print(f"[GO2] close error: {exc}")
