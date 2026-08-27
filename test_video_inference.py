import os
import time
from pathlib import Path

import torch

from qwen_object_service import generate_for_videos

VIDEO_PATH = Path("/cvhci/temp/squan/qwen_object_service/samples/testvideo1.mp4")
OUTPUT_PATH = Path("/cvhci/temp/squan/qwen_object_service/output_video_test.txt")


def main():
    if torch.cuda.is_available():
        torch.cuda.reset_peak_memory_stats()
    started = time.perf_counter()
    result = generate_for_videos([VIDEO_PATH])
    elapsed = time.perf_counter() - started
    peak = torch.cuda.max_memory_allocated() / (1024 ** 3) if torch.cuda.is_available() else 0
    text = (
        f"Video: {VIDEO_PATH}\n"
        "Duration: approximately 5.0 seconds\n"
        f"Inference time: {elapsed:.1f} seconds\n"
        f"Peak torch allocated VRAM: approximately {peak:.2f} GiB\n\n"
        "Result:\n" + result + "\n"
    )
    OUTPUT_PATH.write_text(text, encoding="utf-8")
    print(text)


if __name__ == "__main__":
    main()
