#!/usr/bin/env python3
"""Run a fixed GO2 teleoperation action sequence.

This file only publishes String actions to /vln/uninavid/actions.  Start the
existing ActionTranslator and SafetyGate separately before running it.

Symbols used in the requested sequence:
    l = left, r = right, f = forward, s = stop
"""
from __future__ import annotations

import argparse
import json
import threading
import time

import rclpy
from rclpy.node import Node
from std_msgs.msg import String

ACTION_TOPIC = "/vln/uninavid/actions"
DEFAULT_ACTION_DURATION_SEC = 0.35


def build_sequence() -> list[str]:
    sequence: list[str] = []

    def add(*actions: str) -> None:
        sequence.extend(actions)

    add("left", "forward", "forward", "right")
    add("stop")
    add("right", "right", "left", "left")
    add("stop")
    add("left", "left", "left", "left")
    add("stop")
    add("left", "left", "left", "forward")
    add("stop")
    add("forward", "forward", "forward", "stop")
    add(*(["stop"] * 45))
    add(*(["left"] * 36))
    add("forward", "forward", "right", "right")
    add("stop")
    add("right", "right", "forward", "forward")
    add("stop")
    add("forward", "forward", "left", "left")
    add("left", "left", "forward", "forward")
    add("forward", "forward", "forward", "forward")
    add("forward", "forward", "forward", "forward")
    return sequence


class Go2ActionSequence(Node):
    def __init__(self, action_duration_sec: float, startup_wait_sec: float) -> None:
        super().__init__("go2_action_sequence")
        self.publisher = self.create_publisher(String, ACTION_TOPIC, 10)
        self.action_duration_sec = action_duration_sec
        self.startup_wait_sec = startup_wait_sec
        self.frame_seq = 0
        self.shutdown_requested = threading.Event()

    def publish_action(self, action: str) -> None:
        self.frame_seq += 1
        message = String()
        message.data = json.dumps({
            "frame_seq": self.frame_seq,
            "actions": [action],
        })
        self.publisher.publish(message)
        print(
            f"[ManualSequence] frame_seq={self.frame_seq} "
            f"action={action}",
            flush=True,
        )

    def run(self) -> None:
        sequence = build_sequence()
        print(
            f"[ManualSequence] actions={len(sequence)} "
            f"duration={self.action_duration_sec:.2f}s "
            f"topic={ACTION_TOPIC}",
            flush=True,
        )
        print(
            f"[ManualSequence] waiting {self.startup_wait_sec:.1f}s for subscriber",
            flush=True,
        )
        self.shutdown_requested.wait(self.startup_wait_sec)
        if self.shutdown_requested.is_set():
            return

        for action in sequence:
            if self.shutdown_requested.is_set():
                break
            self.publish_action(action)
            self.shutdown_requested.wait(self.action_duration_sec)

        # Always finish with a stop, including after the requested sequence.
        self.publish_action("stop")
        print("[ManualSequence] complete; final stop published", flush=True)

    def request_stop(self) -> None:
        self.shutdown_requested.set()
        self.publish_action("stop")


def main() -> None:
    parser = argparse.ArgumentParser(description="Run the fixed GO2 action sequence")
    parser.add_argument(
        "--action-duration-sec",
        type=float,
        default=DEFAULT_ACTION_DURATION_SEC,
        help="duration of each action; must match ActionTranslator",
    )
    parser.add_argument("--startup-wait-sec", type=float, default=1.0)
    args = parser.parse_args()
    if args.action_duration_sec <= 0 or args.startup_wait_sec < 0:
        parser.error("action duration must be > 0 and startup wait must be >= 0")

    rclpy.init()
    node = Go2ActionSequence(args.action_duration_sec, args.startup_wait_sec)
    try:
        node.run()
    except KeyboardInterrupt:
        print("[ManualSequence] interrupted; publishing stop", flush=True)
        node.request_stop()
    finally:
        node.destroy_node()
        rclpy.shutdown()


if __name__ == "__main__":
    main()
