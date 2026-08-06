#!/usr/bin/env bash
# 创建本 kits 专用的 Python venv 并安装依赖(openai-whisper, srt)。
# 用法: tools/setup_venv.sh
set -euo pipefail

KITS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="${KITS_DIR}/.venv"

if ! command -v python3 >/dev/null 2>&1; then
  echo "[FAIL] 未找到 python3,请先安装 Python 3.9+"
  exit 1
fi

if [[ ! -d "${VENV_DIR}" ]]; then
  echo "[..] 创建虚拟环境: ${VENV_DIR}"
  python3 -m venv "${VENV_DIR}"
fi

"${VENV_DIR}/bin/pip" install --upgrade pip >/dev/null
"${VENV_DIR}/bin/pip" install -r "${KITS_DIR}/requirements.txt"

echo "[OK] venv 就绪: ${VENV_DIR}"
echo "     运行 tools/check_env.sh 验证环境。"
