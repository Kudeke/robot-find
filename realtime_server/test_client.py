# coding: utf-8
import argparse
import asyncio
import base64
import json
from pathlib import Path

import websockets

VALID_ACTIONS = {"forward", "left", "right", "stop"}


def project_root() -> Path:
    return Path(__file__).resolve().parents[1]


def load_instruction(test_case: Path) -> str:
    instruction_path = test_case / "instruction.json"
    with instruction_path.open("r", encoding="utf-8") as f:
        data = json.load(f)
    instruction = data.get("instruction")
    if not isinstance(instruction, str) or not instruction.strip():
        raise ValueError(f"missing instruction in {instruction_path}")
    return instruction


def first_jpeg(test_case: Path) -> Path:
    image_dir = test_case / "images"
    candidates = []
    for path in image_dir.iterdir():
        if path.suffix.lower() not in {".jpg", ".jpeg"}:
            continue
        try:
            number = int(path.stem)
        except ValueError:
            continue
        candidates.append((number, path))
    if not candidates:
        raise FileNotFoundError(f"no numeric JPEG found in {image_dir}")
    candidates.sort(key=lambda item: item[0])
    return candidates[0][1]


def assert_actions(actions) -> None:
    if not isinstance(actions, list) or not actions:
        raise AssertionError("actions must be a non-empty list")
    invalid = [action for action in actions if action not in VALID_ACTIONS]
    if invalid:
        raise AssertionError(f"invalid actions: {invalid}")


async def run_test(url: str, test_case: Path, session_id: str) -> None:
    instruction = load_instruction(test_case)
    image_path = first_jpeg(test_case)
    jpeg_base64 = base64.b64encode(image_path.read_bytes()).decode("ascii")

    async with websockets.connect(url, ping_interval=None, ping_timeout=None) as ws:
        await ws.send(json.dumps({"type": "ping"}))
        pong = json.loads(await ws.recv())
        if pong.get("type") != "pong":
            raise AssertionError(f"unexpected ping response: {pong}")
        print("[TEST] pong ok")

        await ws.send(
            json.dumps(
                {
                    "type": "reset",
                    "session_id": session_id,
                    "instruction": instruction,
                }
            )
        )
        reset_ack = json.loads(await ws.recv())
        if reset_ack.get("type") != "reset_ack":
            raise AssertionError(f"unexpected reset response: {reset_ack}")
        print("[TEST] reset ok")

        await ws.send(
            json.dumps(
                {
                    "type": "infer",
                    "session_id": session_id,
                    "frame_seq": 1,
                    "timestamp_ns": 0,
                    "jpeg_base64": jpeg_base64,
                }
            )
        )
        result = json.loads(await ws.recv())
        print(json.dumps(result, ensure_ascii=False, indent=2))
        if result.get("type") != "inference_result":
            raise AssertionError(f"unexpected inference response: {result}")
        assert_actions(result.get("actions"))
        if result.get("inference_ms", -1) < 0:
            raise AssertionError("inference_ms must be >= 0")
        print("[TEST] inference ok")
        print(f"[TEST] actions={result['actions']}")

        await ws.send(
            json.dumps({"type": "shutdown_session", "session_id": session_id})
        )
        shutdown_ack = json.loads(await ws.recv())
        if shutdown_ack.get("type") != "shutdown_session_ack":
            raise AssertionError(f"unexpected shutdown response: {shutdown_ack}")
        print("[TEST] shutdown_session ok")

    print("=========================")
    print("REALTIME SERVER PASSED")
    print("=========================")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="ws://127.0.0.1:9000")
    parser.add_argument("--session-id", default="go2")
    parser.add_argument("--test-case", default=str(project_root() / "test_cases/vln_1"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    asyncio.run(run_test(args.url, Path(args.test_case), args.session_id))


if __name__ == "__main__":
    main()
