#!/usr/bin/env bash
# 抓取阶段:下载视频元数据、原视频与封面到工作区的视频目录。
#
# 用法:
#   tools/fetch.sh --url URL --workspace DIR [--proxy PROXY]
#
#   --workspace 是【工作区根目录】(可容纳多个视频);本工具会从元数据标题生成
#   安全目录名(空白->_ ,去掉 " ' ,),创建 <workspace>/<视频名称>/ 并在其内产出:
#     info.txt       视频元信息(原标题/作者/上传日期/URL/时长/扩展名/安全标题)
#     video.<ext>    原视频(已存在则跳过)
#     thumbnail.png  封面(已存在则跳过)
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

# 2. 从元数据生成安全标题并创建视频目录
SAFE_TITLE="$(python3 - "$meta_file" <<'PYEOF'
import json, re, sys
meta = json.load(open(sys.argv[1], encoding="utf-8"))
title = meta.get("title") or meta.get("id") or "unknown"
safe = re.sub(r"\s", "_", title)
safe = safe.replace('"', "").replace(",", "").replace("'", "")
print(safe)
PYEOF
)"
[[ -z "$SAFE_TITLE" ]] && SAFE_TITLE="untitled"
VID_DIR="$WORKSPACE/$SAFE_TITLE"
mkdir -p "$VID_DIR"
echo "[fetch] 视频目录: $VID_DIR"

# 3. 写 info.txt(含安全标题,供后续阶段引用 VIDDIR)
python3 - "$meta_file" "$VID_DIR" "$URL" "$SAFE_TITLE" <<'PYEOF'
import json, os, sys

meta_file, vid_dir, url, safe_title = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
meta = json.load(open(meta_file, encoding="utf-8"))

title = meta.get("title") or meta.get("id") or "unknown"
author = meta.get("uploader") or meta.get("channel") or ""
upload_date = meta.get("upload_date") or ""
ext = meta.get("ext") or ""
duration = int(meta.get("duration") or 0)
m, s = divmod(duration, 60)
h, m = divmod(m, 60)
duration_txt = f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"

with open(os.path.join(vid_dir, "info.txt"), "w", encoding="utf-8") as f:
    f.write(f"原标题: {title}\n")
    f.write(f"作者: {author}\n")
    f.write(f"原始URL: {url}\n")
    f.write(f"上传日期: {upload_date}\n")
    f.write(f"时长: {duration_txt}\n")
    f.write(f"扩展名: {ext}\n")
    f.write(f"视频目录: {vid_dir}\n")

print(f"[fetch] 标题: {title}")
print(f"[fetch] 作者: {author}  时长: {duration_txt}")
print(f"[fetch] 视频目录: {vid_dir}")
PYEOF
meta_rc=$?
rm -f "$meta_file"
[[ $meta_rc -ne 0 ]] && { echo "[fetch] 元数据解析失败,请向用户报告。" >&2; exit 1; }

# 4. 封面(存在则跳过;独立模板,避免与视频共用 -o 导致命名错乱)
if [[ -f "$VID_DIR/thumbnail.png" ]]; then
  echo "[fetch] 封面已存在,跳过: $VID_DIR/thumbnail.png"
else
  if ! timeout 180 env "${proxy_env[@]}" yt-dlp --socket-timeout 30 --retries 2 --no-warnings \
    --skip-download --write-thumbnail --convert-thumbnails png \
    -o "$VID_DIR/thumbnail" "$URL" 2>/tmp/fetch_thumb.err; then
    echo "[fetch] 警告:封面下载失败(不影响后续流程)。错误信息:" >&2
    head -c 300 /tmp/fetch_thumb.err >&2
    echo "" >&2
  fi
fi

# 5. 视频(存在则跳过;检查仅限本视频目录;.part 断点文件不算成品,应继续下载续传)
existing_video="$(ls "$VID_DIR"/video.* 2>/dev/null | grep -vE '\.part$' | head -1 || true)"
if [[ -n "$existing_video" ]]; then
  echo "[fetch] 视频已存在,跳过下载: $existing_video"
else
  if ! timeout 600 env "${proxy_env[@]}" yt-dlp --socket-timeout 30 --retries 3 --no-warnings \
    --restrict-filenames -o "$VID_DIR/video.%(ext)s" "$URL" 2>/tmp/fetch_video.err; then
    echo "[fetch] 视频下载失败。错误信息:" >&2
    head -c 500 /tmp/fetch_video.err >&2
    echo "" >&2
    echo "[fetch] 请向用户报告。常见原因:网络中断、需要代理、源站限速、磁盘空间不足。" >&2
    exit 1
  fi
fi

echo "[fetch] 完成:元数据与视频已就绪于 $VID_DIR"
exit 0
