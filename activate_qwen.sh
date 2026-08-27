#!/usr/bin/env bash

export PATH="/cvhci/temp/squan/qwen_object_service/.mamba_env/bin:$PATH"

export HF_HOME=/cvhci/temp/squan/hf_cache
export HUGGINGFACE_HUB_CACHE=/cvhci/temp/squan/hf_cache/hub
export TRANSFORMERS_CACHE=/cvhci/temp/squan/hf_cache/transformers

export QWEN3_VL_MODEL=/cvhci/temp/squan/models/Qwen3-VL-8B-Instruct
