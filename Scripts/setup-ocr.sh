#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
cd "$project_dir"
selecta_support="$HOME/Library/Application Support/Selecta"
selecta_ocr="$selecta_support/OCR"
export UV_CACHE_DIR="$HOME/Library/Caches/org.ra055814ae03f470d982b.selecta/uv"
export UV_PYTHON_INSTALL_DIR="$selecta_ocr/Python"
export HF_HOME="$HOME/Library/Caches/org.ra055814ae03f470d982b.selecta/huggingface"
export PADDLE_PDX_CACHE_HOME="$selecta_ocr/Models"
export PADDLE_PDX_MODEL_SOURCE=bos
export PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True
if ! command -v uv >/dev/null 2>&1; then
  echo '需要 uv：请先安装 https://docs.astral.sh/uv/getting-started/installation/' >&2
  exit 1
fi
mkdir -p "$selecta_ocr"
if [ ! -x "$selecta_ocr/Environment/bin/python" ]; then
  uv venv --python 3.12 "$selecta_ocr/Environment"
fi
uv pip install --python "$selecta_ocr/Environment/bin/python" -r requirements-ocr.lock
"$selecta_ocr/Environment/bin/python" Selecta/Resources/paddle_ocr.py --prepare --models "$selecta_ocr/Models"
echo '安装完成。Selecta 设置 → 离线 OCR → 百度 PaddleOCR，即可离线识别。'
