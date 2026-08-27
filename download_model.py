from huggingface_hub import snapshot_download

repo_id = "Qwen/Qwen3-VL-8B-Instruct"
local_dir = "/cvhci/temp/squan/models/Qwen3-VL-8B-Instruct"

path = snapshot_download(
    repo_id=repo_id,
    local_dir=local_dir,
)

print(f"Model downloaded to: {path}")
