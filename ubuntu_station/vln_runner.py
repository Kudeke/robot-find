"""Mock VLN runner with conservative default behavior."""

from __future__ import annotations

import select
import sys
import termios
import tty
from dataclasses import dataclass
from typing import Any

import numpy as np


@dataclass(frozen=True)
class CmdVel:
    vx: float
    vy: float
    yaw_rate: float
    duration: float


class MockVLNRunner:
    """Replace this class with a real VLN model runner later.

    The default command is always stop. Optional keyboard control is intended
    only for local testing in a terminal.
    """

    ACTION_KEYS = {
        "w": "forward",
        "a": "turn_left",
        "d": "turn_right",
        "s": "stop",
        " ": "stop",
    }

    def __init__(self, config: dict[str, Any]) -> None:
        self.default_action = str(config.get("default_action", "stop"))
        self.action = str(config.get("test_action", self.default_action))
        if self.action not in {"forward", "turn_left", "turn_right", "stop"}:
            self.action = "stop"
        self.max_vx = float(config.get("max_vx", 0.5))
        self.max_yaw_rate = float(config.get("max_yaw_rate", 0.8))
        self.duration = float(config.get("cmd_duration", 0.2))
        self.keyboard_enabled = bool(config.get("keyboard_enabled", True))
        self._term_settings: list[Any] | None = None

        if self.keyboard_enabled and sys.stdin.isatty():
            self._term_settings = termios.tcgetattr(sys.stdin)
            tty.setcbreak(sys.stdin.fileno())

    def close(self) -> None:
        if self._term_settings is not None:
            termios.tcsetattr(sys.stdin, termios.TCSADRAIN, self._term_settings)
            self._term_settings = None

    def infer(self, frame_bgr: np.ndarray, state: dict[str, Any]) -> CmdVel:
        _ = frame_bgr, state
        self._poll_keyboard()
        return self._action_to_cmd(self.action)

    def _poll_keyboard(self) -> None:
        if not self.keyboard_enabled or self._term_settings is None:
            return

        readable, _, _ = select.select([sys.stdin], [], [], 0.0)
        if not readable:
            return

        key = sys.stdin.read(1)
        action = self.ACTION_KEYS.get(key)
        if action is not None:
            self.action = action

    def _action_to_cmd(self, action: str) -> CmdVel:
        if action == "forward":
            return CmdVel(self.max_vx, 0.0, 0.0, self.duration)
        if action == "turn_left":
            return CmdVel(0.0, 0.0, self.max_yaw_rate, self.duration)
        if action == "turn_right":
            return CmdVel(0.0, 0.0, -self.max_yaw_rate, self.duration)
        return CmdVel(0.0, 0.0, 0.0, 0.0)
