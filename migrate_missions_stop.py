"""One-time idempotent migration for Phase 3A mission snapshots."""
import json
import os
from pathlib import Path

root = Path(os.environ.get("FINDMYTHINGS_DATA_DIR", "/cvhci/temp/squan/qwen_object_service/data")) / "missions"
changed = 0
for path in sorted(root.glob("mission_*.json")):
    data = json.loads(path.read_text(encoding="utf-8"))
    instruction = data.get("navigation_instruction")
    if isinstance(instruction, str) and instruction.strip() and not instruction.rstrip().lower().endswith("and stop."):
        data["navigation_instruction"] = instruction.rstrip().rstrip(".") + " and stop."
        path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        changed += 1
print(f"Updated mission files: {changed}")
