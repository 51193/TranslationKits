#!/usr/bin/env bash
# 烧录阶段:将字幕烧录进视频(可选,默认关闭)。
#
# 用法:
#   tools/burn.sh --video <video> --subtitle <subtitle.srt> --output <out.mp4> \
#                 [--gpu auto|cpu|vaapi] [--vaapi-device /dev/dri/renderD128] \
#                 [--encoder libx264] [--enforce-source-bitrate] [--min-bitrate-kbps N]
#
# GPU 行为(与 transcribe.py 对齐:显式检查,不可用时提示询问,不默默降级):
#   --gpu auto  (默认) 检测 vaapi 编码器与 /dev/dri/renderD* 设备:
#                       可用 -> 使用 h264_vaapi 硬件编码(打印所用 GPU);
#                       不可用 -> 回退 CPU 软件编码,并打印 [WARN] 提示:
#                       agent 应向用户确认是否接受 CPU 烧录。
#   --gpu vaapi         强制硬件编码;环境不支持时 FAIL(exit 1),由 agent 询问用户降级。
#   --gpu cpu           强制软件编码(不打印 GPU 提示)。
#
# 其他:
#   --enforce-source-bitrate 时,用 ffprobe 读取原视频码率,
#   输出码率下限 = max(原视频码率, --min-bitrate-kbps)。
set -uo pipefail

usage() {
  echo "用法: burn.sh --video <video> --subtitle <subtitle.srt> --output <out.mp4> [--gpu auto|cpu|vaapi] [--vaapi-device DEV] [--encoder libx264] [--enforce-source-bitrate] [--min-bitrate-kbps N]" >&2
  exit 1
}

VIDEO=""
SUBTITLE=""
OUTPUT=""
ENCODER=""
GPU_MODE="auto"
VAAPI_DEVICE=""
ENFORCE=0
MIN_KBPS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video) VIDEO="${2:-}"; shift 2 ;;
    --subtitle) SUBTITLE="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --gpu) GPU_MODE="${2:-auto}"; shift 2 ;;
    --vaapi-device) VAAPI_DEVICE="${2:-}"; shift 2 ;;
    --encoder) ENCODER="${2:-}"; shift 2 ;;
    --enforce-source-bitrate) ENFORCE=1; shift ;;
    --min-bitrate-kbps) MIN_KBPS="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$VIDEO" && -n "$SUBTITLE" && -n "$OUTPUT" ]] || usage
[[ -f "$VIDEO" ]] || { echo "[burn] FAIL 视频不存在: $VIDEO" >&2; exit 1; }
[[ -f "$SUBTITLE" ]] || { echo "[burn] FAIL 字幕不存在: $SUBTITLE" >&2; exit 1; }
[[ "$GPU_MODE" =~ ^(auto|cpu|vaapi)$ ]] || { echo "[burn] FAIL --gpu 只能是 auto|cpu|vaapi" >&2; exit 1; }
[[ -f "$OUTPUT" ]] && { echo "[burn] 输出已存在,跳过: $OUTPUT"; exit 0; }

# ---- GPU 检测(与 transcribe.py 对齐)----
# 注意:先完整捕获 ffmpeg -encoders 输出再 grep,避免 pipefail 下
# grep -q 提前关闭管道导致 ffmpeg SIGPIPE 使 pipeline 判为失败。
VAAPI_OK=0
FF_ENCODERS="$(ffmpeg -hide_banner -encoders 2>/dev/null)"
if [[ "$FF_ENCODERS" == *"h264_vaapi"* ]]; then
  if [[ -z "$VAAPI_DEVICE" ]]; then
    for dev in /dev/dri/renderD128 /dev/dri/renderD129; do
      [[ -e "$dev" ]] && VAAPI_DEVICE="$dev" && break
    done
  fi
  [[ -n "$VAAPI_DEVICE" && -e "$VAAPI_DEVICE" ]] && VAAPI_OK=1
fi

USE_VAAPI=0
case "$GPU_MODE" in
  vaapi)
    if [[ $VAAPI_OK -eq 1 ]]; then
      USE_VAAPI=1
    else
      echo "[burn] FAIL 要求 GPU(vaapi)编码,但环境不支持(缺 h264_vaapi 编码器或 render 设备)。" >&2
      echo "[burn] 请向用户确认:修复 GPU 环境,或降级为 CPU 烧录(--gpu cpu),或放弃烧录。" >&2
      exit 1
    fi
    ;;
  auto)
    if [[ $VAAPI_OK -eq 1 ]]; then
      USE_VAAPI=1
      echo "[burn] 检测到 GPU 编码可用(vaapi 设备: $VAAPI_DEVICE),使用硬件编码。"
    else
      echo "[burn] WARN 未检测到可用 GPU 编码(缺 h264_vaapi 或 render 设备),将使用 CPU 软件编码。"
      echo "[burn] WARN 若用户要求 GPU 编码,请先询问确认是否接受 CPU 烧录。"
    fi
    ;;
  cpu)
    echo "[burn] 按用户决定使用 CPU 软件编码。"
    ;;
esac

# ---- 码率参数 ----
BITRATE_ARGS=""
if [[ $ENFORCE -eq 1 ]]; then
  src_bps="$(ffprobe -v error -select_streams v:0 -show_entries stream=bit_rate -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null | tr -d '[:space:]')"
  if [[ -z "$src_bps" || "$src_bps" == "N/A" ]]; then
    src_bps="$(ffprobe -v error -show_entries format=bit_rate -of default=noprint_wrappers=1:nokey=1 "$VIDEO" 2>/dev/null | tr -d '[:space:]')"
  fi
  if [[ -n "$src_bps" && "$src_bps" != "N/A" && "$src_bps" =~ ^[0-9]+$ ]]; then
    src_kbps=$(( (src_bps + 999) / 1000 ))
    target=$(( src_kbps > MIN_KBPS ? src_kbps : MIN_KBPS ))
    echo "[burn] 原视频码率 ${src_kbps}kbps,输出码率下限 ${target}kbps"
    BITRATE_ARGS="-b:v ${target}k -maxrate ${target}k -bufsize $(( target * 2 ))k"
  else
    echo "[burn] 警告: 无法读取原视频码率,回退默认编码策略。" >&2
  fi
fi

# ---- 滤镜与编码参数 ----
escape_filter() {
  local p="$1"
  p="${p//\\/\\\\}"
  p="${p//:/\\:}"
  p="${p//,/\\,}"
  printf '%s' "$p"
}

if [[ $USE_VAAPI -eq 1 ]]; then
  # GPU 编码:字幕滤镜(CPU) -> nv12 -> hwupload -> h264_vaapi
  VAAPI_ARGS="-vaapi_device $VAAPI_DEVICE"
  VF="subtitles=$(escape_filter "$SUBTITLE"),format=nv12,hwupload"
  ENC_ARGS="-c:v h264_vaapi $BITRATE_ARGS"
else
  VAAPI_ARGS=""
  VF="subtitles=$(escape_filter "$SUBTITLE")"
  if [[ -n "$ENCODER" ]]; then
    ENC_ARGS="-c:v $ENCODER $BITRATE_ARGS"
  else
    ENC_ARGS="$BITRATE_ARGS"
  fi
fi

echo "[burn] ffmpeg $VAAPI_ARGS -i '$VIDEO' -vf '$VF' $ENC_ARGS -c:a copy '$OUTPUT'"
if ! ffmpeg -hide_banner -loglevel warning -y \
  $VAAPI_ARGS -i "$VIDEO" -vf "$VF" $ENC_ARGS -c:a copy "$OUTPUT" 2>/tmp/burn.err; then
  echo "[burn] FAIL 烧录失败,错误信息:" >&2
  head -c 500 /tmp/burn.err >&2
  echo "" >&2
  exit 1
fi

echo "[burn] 完成: $OUTPUT"
exit 0
