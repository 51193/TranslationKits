#!/usr/bin/env bash
# 环境预检:字幕翻译工作流起步时必须运行的第一个工具。
# 检查:必需二进制、Python venv / whisper、GPU(CUDA/ROCm)、工作区可写与磁盘空间、URL 连通性。
#
# 用法:
#   tools/check_env.sh [--workspace DIR] [--url URL] [--proxy PROXY]
#
# 退出码:
#   0 = 全部通过,可开始流程
#   1 = 存在致命问题(FAIL),禁止继续,按文档处置或询问用户
#   2 = 仅有警告(WARN),可继续但需注意
#
# 输出行格式: [OK] / [WARN] / [FAIL] 描述,便于解析。
set -uo pipefail

KITS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE=""
URL=""
PROXY=""

usage() {
  echo "用法: check_env.sh [--workspace DIR] [--url URL] [--proxy PROXY]" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --url) URL="${2:-}"; shift 2 ;;
    --proxy) PROXY="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

# ---- 辅助 ----
FAILS=0
WARNS=0

fail() { echo "[FAIL] $1"; FAILS=$((FAILS+1)); }
warn() { echo "[WARN] $1"; WARNS=$((WARNS+1)); }
ok()   { echo "[OK]   $1"; }

proxy_env=()
if [[ -n "$PROXY" ]]; then
  proxy_env=(http_proxy="$PROXY" https_proxy="$PROXY" all_proxy="$PROXY")
  ok "使用显式代理: $PROXY"
fi

echo "==== 1. 必需二进制 ===="
for bin in yt-dlp ffmpeg ffprobe python3; do
  if command -v "$bin" >/dev/null 2>&1; then
    ok "$bin: $(command -v "$bin")"
  else
    fail "未找到 $bin,请安装后重试(apt install yt-dlp ffmpeg python3)"
  fi
done

if command -v node >/dev/null 2>&1; then
  ok "node: $(command -v node)"
else
  warn "未找到 node;yt-dlp 的 --js-runtimes node 将不可用,部分网站(如 YouTube)可能下载失败。建议安装 nodejs。"
fi

if command -v yt-dlp >/dev/null 2>&1; then
  ver="$(yt-dlp --version 2>/dev/null || echo unknown)"
  ok "yt-dlp 版本: $ver"
fi

echo "==== 2. Python / Whisper 环境 ===="
WHISPER_PY=""
if [[ -x "${KITS_DIR}/.venv/bin/python3" ]]; then
  WHISPER_PY="${KITS_DIR}/.venv/bin/python3"
  ok "使用 kits 虚拟环境: ${KITS_DIR}/.venv"
else
  WHISPER_PY="$(command -v python3 || true)"
  warn "未找到 ${KITS_DIR}/.venv,回退系统 python3。若提示缺少 whisper,请运行 tools/setup_venv.sh"
fi

if [[ -n "$WHISPER_PY" ]] && "$WHISPER_PY" -c "import whisper, srt" >/dev/null 2>&1; then
  ok "whisper + srt 模块可用"
else
  fail "whisper 或 srt 模块缺失。请运行: tools/setup_venv.sh"
fi

echo "==== 3. GPU 计算设备 (CUDA/ROCm) ===="
GPU_DETECT="$(
  "$WHISPER_PY" -c '
import torch
if torch.cuda.is_available():
    print("cuda:" + torch.cuda.get_device_name(0) if torch.cuda.device_count() > 0 else "cuda")
elif getattr(torch.version, "hip", None):
    print("rocm:ROCm " + str(torch.version.hip))
else:
    print("cpu")
' 2>/dev/null || echo "unknown"
)"
case "$GPU_DETECT" in
  cuda*) ok "CUDA 可用: ${GPU_DETECT#cuda:};whisper 将使用 GPU 加速" ;;
  rocm*) ok "ROCm 可用: ${GPU_DETECT#rocm:};whisper 将使用 GPU 加速" ;;
  cpu)   warn "未检测到 GPU,whisper 将以 CPU 运行,速度较慢" ;;
  unknown) warn "无法检测 torch 设备信息(可能 torch 缺失);以 CPU 兜底" ;;
esac

echo "==== 4. 工作区检查 ===="
if [[ -n "$WORKSPACE" ]]; then
  mkdir -p "$WORKSPACE" 2>/dev/null
  if [[ -d "$WORKSPACE" && -w "$WORKSPACE" ]]; then
    ok "工作区可用: $WORKSPACE"
    free_kb="$(df -Pk "$WORKSPACE" 2>/dev/null | awk 'NR==2 {print $4}')"
    if [[ -n "$free_kb" && "$free_kb" -lt 5242880 ]]; then
      warn "工作区所在磁盘剩余空间不足 5GB(当前 $(numfmt --to=iec "$((free_kb * 1024))" 2>/dev/null || echo "$free_kb KB")),大视频下载可能失败"
    else
      ok "磁盘空间充足: $(numfmt --to=iec "$((free_kb * 1024))" 2>/dev/null || echo "$free_kb KB")"
    fi
  else
    fail "工作区不存在或不可写: $WORKSPACE"
  fi
else
  warn "未提供 --workspace,跳过工作区检查"
fi

echo "==== 5. URL 连通性 ===="
if [[ -n "$URL" ]]; then
  timeout 60 env "${proxy_env[@]}" yt-dlp --socket-timeout 20 --retries 1 --no-warnings \
    --skip-download --simulate --print '%(title)s' --print '%(channel)s' "$URL" \
    >/tmp/check_env_title.out 2>/tmp/check_env_ytdlp.err
  yt_code=$?
  TITLE="$(cat /tmp/check_env_title.out 2>/dev/null)"
  if [[ $yt_code -eq 0 && -n "$TITLE" ]]; then
    ok "URL 可访问,yt-dlp 可提取: $(echo "$TITLE" | head -1)"
  else
    host="$(printf '%s' "$URL" | sed -E 's#^[a-z]+://##; s#/.*$##')"
    if curl -sI --max-time 10 "${proxy_env[@]}" "https://$host" >/dev/null 2>&1; then
      fail "URL 网络可达但 yt-dlp 提取失败(可能需登录、视频私有、或站点限制)。错误: $(head -c 300 /tmp/check_env_ytdlp.err | tr '\n' ' ')。请向用户确认 URL 有效性或授权。"
    else
      if [[ -n "$PROXY" || -n "${ALL_PROXY:-}" || -n "${HTTPS_PROXY:-}" ]]; then
        fail "无法连通 $host(已配置代理仍失败)。请向用户确认代理地址是否正确,或检查网络。"
      else
        fail "无法连通 $host:可能需要代理。请向用户询问是否提供代理(--proxy),取得后重跑本工具。"
      fi
    fi
  fi
else
  warn "未提供 --url,跳过连通性检查"
fi

echo "==== 预检结果 ===="
if [[ $FAILS -gt 0 ]]; then
  echo "[FAIL] $FAILS 个致命问题,$WARNS 个警告。禁止继续,按 tools/check_env.sh 输出与工作流文档处置。"
  exit 1
elif [[ $WARNS -gt 0 ]]; then
  echo "[WARN] $WARNS 个警告(不阻塞),可以继续。"
  exit 2
fi
echo "[OK] 环境全部就绪,可以开始工作流。"
exit 0
