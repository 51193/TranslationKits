#!/usr/bin/env bash
# 烧录阶段:将字幕烧录进视频(可选,默认关闭)。
# 用法:
#   tools/burn.sh --video <video> --subtitle <subtitle.srt> --output <out.mp4> \
#                 [--encoder libx264] [--enforce-source-bitrate] [--min-bitrate-kbps N]
#
# 行为:
#   - 默认按 ffmpeg 原生编码(不指定 c:v);
#   - 指定 --enforce-source-bitrate 时,用 ffprobe 读取原视频码率,
#     输出码率下限 = max(原视频码率, --min-bitrate-kbps);
#   - 对字幕路径做 ffmpeg 过滤转义;工作区路径不应含特殊字符。
set -uo pipefail

usage() {
  echo "用法: burn.sh --video <video> --subtitle <subtitle.srt> --output <out.mp4> [--encoder libx264] [--enforce-source-bitrate] [--min-bitrate-kbps N]" >&2
  exit 1
}

VIDEO=""
SUBTITLE=""
OUTPUT=""
ENCODER=""
ENFORCE=0
MIN_KBPS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --video) VIDEO="${2:-}"; shift 2 ;;
    --subtitle) SUBTITLE="${2:-}"; shift 2 ;;
    --output) OUTPUT="${2:-}"; shift 2 ;;
    --encoder) ENCODER="${2:-}"; shift 2 ;;
    --enforce-source-bitrate) ENFORCE=1; shift ;;
    --min-bitrate-kbps) MIN_KBPS="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$VIDEO" && -n "$SUBTITLE" && -n "$OUTPUT" ]] || usage
[[ -f "$VIDEO" ]] || { echo "[burn] FAIL 视频不存在: $VIDEO" >&2; exit 1; }
[[ -f "$SUBTITLE" ]] || { echo "[burn] FAIL 字幕不存在: $SUBTITLE" >&2; exit 1; }
[[ -f "$OUTPUT" ]] && { echo "[burn] 输出已存在,跳过: $OUTPUT"; exit 0; }

# ffmpeg subtitles 滤镜转义
escape_filter() {
  local p="$1"
  p="${p//\\/\\\\}"
  p="${p//:/\\:}"
  p="${p//,/\\,}"
  printf '%s' "$p"
}

VF="subtitles=$(escape_filter "$SUBTITLE")"

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

if [[ -n "$ENCODER" ]]; then
  ENC_ARGS="-c:v $ENCODER $BITRATE_ARGS"
else
  ENC_ARGS="$BITRATE_ARGS"
fi

echo "[burn] ffmpeg -i '$VIDEO' -vf '$VF' $ENC_ARGS -c:a copy '$OUTPUT'"
if ! ffmpeg -hide_banner -loglevel warning -y \
  -i "$VIDEO" -vf "$VF" $ENC_ARGS -c:a copy "$OUTPUT" 2>/tmp/burn.err; then
  echo "[burn] FAIL 烧录失败,错误信息:" >&2
  head -c 500 /tmp/burn.err >&2
  echo "" >&2
  exit 1
fi

echo "[burn] 完成: $OUTPUT"
exit 0
