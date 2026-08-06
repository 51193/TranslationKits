#!/usr/bin/env bash
# 抓取阶段:下载视频元数据、原视频与封面到工作区。
# 用法:
#   tools/fetch.sh --url URL --workspace DIR [--proxy PROXY]
#
# 产物:
#   <workspace>/info.txt       视频元信息(原标题/作者/上传日期/URL/时长/扩展名)
#   <workspace>/video.<ext>    原视频(已存在则跳过)
#   <workspace>/thumbnail.png  封面(已存在则跳过)
#
# 退出码:0=成功;1=失败(向用户报告,不要自行调试)
set -uo pipefail

usage() {
  echo "用法: fetch.sh --url URL --workspace DIR [--proxy PROXY]" >&2
  exit 1
}

URL=""
WORKSPACE=""
PROXY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --url) URL="${2:-}"; shift 2 ;;
    --workspace) WORKSPACE="${2:-}"; shift 2 ;;
    --proxy) PROXY="${2:-}"; shift 2 ;;
    *) usage ;;
  esac
done

[[ -n "$URL" && -n "$WORKSPACE" ]] || usage

mkdir -p "$WORKSPACE"

proxy_env=()
if [[ -n "$PROXY" ]]; then
  proxy_env=(http_proxy="$PROXY" https_proxy="$PROXY" all_proxy="$PROXY")
  echo "[fetch] 使用代理: $PROXY"
fi

# 1. 元数据
meta_file="$(mktemp)"
if ! timeout 180 env "${proxy_env[@]}" yt-dlp --socket-timeout 30 --retries 2 --no-warnings \
  --dump-json --skip-download "$URL" >"$meta_file" 2>/tmp/fetch_meta.err; then
  echo "[fetch] 元数据获取失败。错误信息:" >&2
  head -c 500 /tmp/fetch_meta.err >&2
  echo "" >&2
  echo "[fetch] 请向用户报告,不要自行调整参数。常见原因:URL 无效、需登录、地区限制、需要代理。" >&2
  rm -f "$meta_file"
  exit 1
fi

python3 - "$meta_file" "$WORKSPACE" "$URL" <<'PYEOF'
import json, sys, os

meta_file, workspace, url = sys.argv[1], sys.argv[2], sys.argv[3]
meta = json.load(open(meta_file, encoding="utf-8"))

title = meta.get("title") or meta.get("id") or "unknown"
author = meta.get("uploader") or meta.get("channel") or ""
upload_date = meta.get("upload_date") or ""
ext = meta.get("ext") or ""
duration = int(meta.get("duration") or 0)
m, s = divmod(duration, 60)
h, m = divmod(m, 60)
duration_txt = f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"

with open(os.path.join(workspace, "info.txt"), "w", encoding="utf-8") as f:
    f.write(f"原标题: {title}\n")
    f.write(f"作者: {author}\n")
    f.write(f"原始URL: {url}\n")
    f.write(f"上传日期: {upload_date}\n")
    f.write(f"时长: {duration_txt}\n")
    f.write(f"扩展名: {ext}\n")

print(json.dumps({
    "title": title, "author": author, "upload_date": upload_date,
    "duration": duration, "ext": ext,
}, ensure_ascii=False))
PYEOF
meta_rc=$?
rm -f "$meta_file"
[[ $meta_rc -ne 0 ]] && { echo "[fetch] 元数据解析失败,请向用户报告。" >&2; exit 1; }

# 2. 视频(存在则跳过)
if ls "$WORKSPACE"/video.* >/dev/null 2>&1; then
  echo "[fetch] 视频已存在,跳过下载: $(ls "$WORKSPACE"/video.* | head -1)"
else
  if ! timeout 600 env "${proxy_env[@]}" yt-dlp --socket-timeout 30 --retries 3 --no-warnings \
    --restrict-filenames --write-thumbnail --convert-thumbnails png \
    -o "$WORKSPACE/video.%(ext)s" "$URL" 2>/tmp/fetch_video.err; then
    echo "[fetch] 视频下载失败。错误信息:" >&2
    head -c 500 /tmp/fetch_video.err >&2
    echo "" >&2
    echo "[fetch] 请向用户报告。常见原因:网络中断、需要代理、源站限速、磁盘空间不足。" >&2
    exit 1
  fi
fi

if [[ ! -f "$WORKSPACE/thumbnail.png" ]]; then
  echo "[fetch] 警告:封面文件未生成(thumbnail.png),不影响后续流程,忽略。" >&2
fi

echo "[fetch] 完成:视频与元数据已就绪于 $WORKSPACE"
exit 0
