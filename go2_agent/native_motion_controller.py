import json
import socket
import threading
from typing import Optional

from native_stop_controller import NativeStopController


class NativeMotionController:
    def __init__(
        self,
        socket_path="/tmp/go2_motion_daemon.sock",
        connect_timeout_sec=2.0,
        request_timeout_sec=1.0,
        fallback_stop_controller: Optional[NativeStopController] = None,
    ):
        self.socket_path = socket_path
        self.connect_timeout_sec = float(connect_timeout_sec)
        self.request_timeout_sec = float(request_timeout_sec)
        self.fallback_stop_controller = fallback_stop_controller
        self._lock = threading.Lock()
        self._sock = None
        self._seq = 0

    def connect(self):
        with self._lock:
            return self._connect_locked()

    def _connect_locked(self):
            if self._sock is not None:
                return True
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.settimeout(self.connect_timeout_sec)
                sock.connect(self.socket_path)
                sock.settimeout(self.request_timeout_sec)
                self._sock = sock
                print(f"[GO2][NATIVE_MOTION] connected socket={self.socket_path}")
                return True
            except Exception as exc:
                print(f"[GO2][NATIVE_MOTION] connect failed: {exc}")
                self._close_locked()
                return False

    def move(self, vx, vy, yaw_rate):
        with self._lock:
            self._seq += 1
            seq = self._seq
            response = self._request_locked(
                {"type": "move", "seq": seq, "vx": vx, "vy": vy, "yaw": yaw_rate}
            )
            if response.get("type") != "move_ack" or not response.get("accepted", False):
                raise RuntimeError(f"move rejected: {response}")
            return response

    def stop(self):
        with self._lock:
            self._seq += 1
            seq = self._seq
            try:
                response = self._request_locked({"type": "stop", "seq": seq})
                if response.get("type") != "stop_ack":
                    raise RuntimeError(f"unexpected stop response: {response}")
                return response
            except Exception as exc:
                print(f"[GO2][NATIVE_MOTION] stop failed: {exc}")
                if self.fallback_stop_controller is not None:
                    self.fallback_stop_controller.stop()
                raise

    def status(self):
        with self._lock:
            response = self._request_locked({"type": "status"})
            try:
                self._seq = max(self._seq, int(response.get("last_seq", self._seq)))
            except (TypeError, ValueError):
                pass
            return response

    def close(self):
        with self._lock:
            if self._sock is not None:
                try:
                    self._seq += 1
                    self._request_locked({"type": "stop", "seq": self._seq})
                except Exception as exc:
                    print(f"[GO2][NATIVE_MOTION] close stop failed: {exc}")
                    if self.fallback_stop_controller is not None:
                        self.fallback_stop_controller.stop()
            self._close_locked()

    def _request_locked(self, payload):
        if self._sock is None and not self._connect_locked():
            raise RuntimeError("not connected to motion daemon")
        line = json.dumps(payload, separators=(",", ":")) + "\n"
        try:
            self._sock.sendall(line.encode("utf-8"))
            response_line = self._recv_line_locked()
            return json.loads(response_line)
        except Exception as exc:
            print(f"[GO2][NATIVE_MOTION] request failed: {exc}")
            self._close_locked()
            if self.fallback_stop_controller is not None:
                self.fallback_stop_controller.stop()
            raise

    def _recv_line_locked(self):
        chunks = []
        while True:
            chunk = self._sock.recv(1)
            if not chunk:
                raise RuntimeError("motion daemon disconnected")
            if chunk == b"\n":
                return b"".join(chunks).decode("utf-8")
            if chunk != b"\r":
                chunks.append(chunk)

    def _close_locked(self):
        if self._sock is not None:
            try:
                self._sock.close()
            finally:
                self._sock = None
