#!/usr/bin/env bash

export MAMBA_ROOT_PREFIX=/cvhci/temp/squan/Navila/micromamba-root

eval "$(/cvhci/temp/squan/Navila/micromamba-bin/micromamba shell hook -s bash)"

micromamba activate uninavid

export CUDA_VISIBLE_DEVICES=2

cd /cvhci/temp/squan/uninavid

echo "Environment: $(which python)"
echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"