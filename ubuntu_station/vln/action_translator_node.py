import argparse
import json
import threading
import time
from typing import Any

import rclpy
from geometry_msgs.msg import Twist
from rclpy.node import Node
from std_msgs.msg import String


VALID_ACTIONS = {"forward", "left", "right", "stop"}
STATUS_TOPIC = "/vln/action_translator/status"


class ActionTranslatorDryRunNode(Node):
    def __init__(
        self,
        input_topic: str,
        output_topic: str,
        forward_speed: float,
        turn_speed: float,
        action_duration_sec: float,
        max_actions: int,
        max_action_age_sec: float,
    ) -> None:
        super().__init__("uninavid_action_translator_dryrun")
        if output_topic == "/cmd_vel":
            raise ValueError("Refusing to publish to production /cmd_vel")
        if action_duration_sec <= 0:
            raise ValueError("--action-duration-sec must be greater than zero")
        if max_actions <= 0:
            raise ValueError("--max-actions must be greater than zero")

        self.input_topic = input_topic
        self.output_topic = output_topic
        self.forward_speed = float(forward_speed)
        self.turn_speed = float(turn_speed)
        self.action_duration_sec = float(action_duration_sec)
        self.max_actions = int(max_actions)
        self.max_action_age_sec = float(max_action_age_sec)

        self.lock = threading.Lock()
        self.condition = threading.Condition(self.lock)
        self.queue: list[str] = []
        self.active_frame_seq: int | None = None
        self.last_frame_seq: int | None = None
        self.generation = 0
        self.shutdown_requested = False
        self.executing = False

        self.cmd_pub = self.create_publisher(Twist, output_topic, 10)
        self.status_pub = self.create_publisher(String, STATUS_TOPIC, 10)
        self.create_subscription(String, input_topic, self._on_actions, 10)

        self.worker = threading.Thread(
            target=self._worker_loop,
            name="uninavid_action_translator_dryrun",
            daemon=True,
        )
        self.worker.start()
        self._publish_status("idle", None, None, 0)

    def _on_actions(self, msg: String) -> None:
        try:
            payload = json.loads(msg.data)
            if not isinstance(payload, dict):
                raise ValueError("message JSON must be an object")

            frame_seq = int(payload["frame_seq"])
            raw_actions = payload.get("actions")
            if not isinstance(raw_actions, list) or not raw_actions:
                raise ValueError("actions must be a non-empty list")

            actions = [str(action).lower() for action in raw_actions[: self.max_actions]]
            invalid = [action for action in actions if action not in VALID_ACTIONS]
            if invalid:
                raise ValueError(f"unknown actions: {invalid}")

            if self._is_stale_frame_seq(frame_seq):
                print(
                    f"[TRANSLATOR] stale frame ignored frame_seq={frame_seq}",
                    flush=True,
                )
                self._publish_status("stale_message", frame_seq, None, 0)
                return

            if self._is_expired(payload):
                print(
                    f"[TRANSLATOR] expired frame ignored frame_seq={frame_seq}",
                    flush=True,
                )
                self._replace_queue(frame_seq, [])
                self._publish_stop()
                self._publish_status("stale_message", frame_seq, None, 0)
                return

            print(f"[TRANSLATOR] frame_seq={frame_seq} actions={actions}", flush=True)
            replaced = self._replace_queue(frame_seq, actions)
            if replaced:
                print(
                    f"[TRANSLATOR] replaced old queue with frame_seq={frame_seq}",
                    flush=True,
                )
                self._publish_status(
                    "replaced_by_newer_frame",
                    frame_seq,
                    None,
                    len(actions),
                )
        except Exception as exc:
            print(f"[TRANSLATOR][ERROR] invalid JSON: {exc}", flush=True)
            self._replace_queue(None, [])
            self._publish_stop()
            self._publish_status("invalid_message", None, None, 0)

    def _is_stale_frame_seq(self, frame_seq: int) -> bool:
        with self.lock:
            return self.last_frame_seq is not None and frame_seq <= self.last_frame_seq

    def _is_expired(self, payload: dict[str, Any]) -> bool:
        timestamp_ns = payload.get("server_timestamp_ns")
        if timestamp_ns is None:
            timestamp_ns = payload.get("source_timestamp_ns")
        if timestamp_ns is None:
            return False
        try:
            timestamp_ns = int(timestamp_ns)
        except (TypeError, ValueError):
            return False
        if timestamp_ns <= 0:
            return False
        age_sec = (time.time_ns() - timestamp_ns) / 1_000_000_000.0
        return age_sec > self.max_action_age_sec

    def _replace_queue(self, frame_seq: int | None, actions: list[str]) -> bool:
        with self.condition:
            replaced = bool(self.queue or self.executing)
            self.queue = list(actions)
            self.active_frame_seq = frame_seq
            if frame_seq is not None:
                self.last_frame_seq = frame_seq
            self.generation += 1
            self.condition.notify_all()
            return replaced

    def _worker_loop(self) -> None:
        while True:
            with self.condition:
                while not self.shutdown_requested and not self.queue:
                    self.condition.wait()
                if self.shutdown_requested:
                    break

                action = self.queue.pop(0)
                frame_seq = self.active_frame_seq
                generation = self.generation
                self.executing = True
                remaining = len(self.queue)

            if action == "stop":
                with self.condition:
                    self.queue = []
                    self.executing = False
                self._publish_stop()
                self._publish_status("stopped", frame_seq, action, 0)
                continue

            twist = self._twist_for_action(action)
            print(
                "[TRANSLATOR][DRYRUN] "
                f"action={action} linear_x={twist.linear.x} angular_z={twist.angular.z}",
                flush=True,
            )
            self._publish_status("executing", frame_seq, action, remaining)
            self.cmd_pub.publish(twist)

            interrupted = self._wait_for_duration_or_replacement(generation)
            self._publish_stop()
            if interrupted:
                self._publish_status("replaced_by_newer_frame", frame_seq, None, 0)

            with self.condition:
                if self.generation == generation:
                    self.executing = False
                    if not self.queue:
                        self._publish_status("idle", frame_seq, None, 0)

        self._publish_stop()
        self._publish_status("shutdown", self.active_frame_seq, None, 0)

    def _wait_for_duration_or_replacement(self, generation: int) -> bool:
        deadline = time.monotonic() + self.action_duration_sec
        with self.condition:
            while not self.shutdown_requested and self.generation == generation:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return False
                self.condition.wait(timeout=remaining)
            return True

    def _twist_for_action(self, action: str) -> Twist:
        twist = Twist()
        if action == "forward":
            twist.linear.x = self.forward_speed
        elif action == "left":
            twist.angular.z = self.turn_speed
        elif action == "right":
            twist.angular.z = -self.turn_speed
        return twist

    def _publish_stop(self) -> None:
        print("[TRANSLATOR][DRYRUN] publish stop", flush=True)
        self.cmd_pub.publish(Twist())

    def _publish_status(
        self,
        state: str,
        frame_seq: int | None,
        current_action: str | None,
        queue_remaining: int,
    ) -> None:
        msg = String()
        msg.data = json.dumps(
            {
                "frame_seq": frame_seq,
                "state": state,
                "current_action": current_action,
                "queue_remaining": int(queue_remaining),
                "dry_run": True,
            },
            separators=(",", ":"),
        )
        self.status_pub.publish(msg)

    def stop(self) -> None:
        with self.condition:
            self.shutdown_requested = True
            self.queue = []
            self.generation += 1
            self.condition.notify_all()
        self._publish_stop()
        if self.worker.is_alive():
            self.worker.join(timeout=2.0)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input-topic", default="/vln/uninavid/actions")
    parser.add_argument("--output-topic", default="/cmd_vel_debug")
    parser.add_argument("--forward-speed", type=float, default=0.12)
    parser.add_argument("--turn-speed", type=float, default=0.25)
    parser.add_argument("--action-duration-sec", type=float, default=0.35)
    parser.add_argument("--max-actions", type=int, default=4)
    parser.add_argument("--max-action-age-sec", type=float, default=2.0)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    rclpy.init()
    node = ActionTranslatorDryRunNode(
        input_topic=args.input_topic,
        output_topic=args.output_topic,
        forward_speed=args.forward_speed,
        turn_speed=args.turn_speed,
        action_duration_sec=args.action_duration_sec,
        max_actions=args.max_actions,
        max_action_age_sec=args.max_action_age_sec,
    )
    try:
        rclpy.spin(node)
    except KeyboardInterrupt:
        print("[TRANSLATOR] shutdown requested", flush=True)
    finally:
        node.stop()
        node.destroy_node()
        if rclpy.ok():
            rclpy.shutdown()


if __name__ == "__main__":
    main()
