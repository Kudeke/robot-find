import json
import time
from pathlib import Path

import torch

from qwen_object_service import generate_profile

VIDEOS = [Path(f"/cvhci/temp/squan/qwen_object_service/samples/testvideo{i}.mp4") for i in range(1, 5)]
OUTPUT = Path("/cvhci/temp/squan/qwen_object_service/output_object_profile_test.json")


def main():
    if torch.cuda.is_available():
        torch.cuda.reset_peak_memory_stats()
    started = time.perf_counter()
    profile, raw = generate_profile(VIDEOS)
    elapsed = time.perf_counter() - started
    payload = {
        "videos": [str(path) for path in VIDEOS],
        "inference_seconds": round(elapsed, 1),
        "peak_torch_allocated_gib": round(torch.cuda.max_memory_allocated() / (1024 ** 3), 2) if torch.cuda.is_available() else 0,
        "profile": profile,
        "raw_model_output": raw,
    }
    OUTPUT.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(payload, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
