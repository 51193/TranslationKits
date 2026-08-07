#!/usr/bin/env python3
# 05 阶段:自动生成交付报告 translation_report.md。
# 报告样板内容(参数/产物/记忆摘要/运行流水/问题)全部由本工具从工作区状态文件生成,
# agent 无需(也不应)手写重复样板;如需补充人工观察,可在文件末尾追加一小节。
#
# 用法:
#   tools/report.py --vid-dir VIDDIR [--output VIDDIR/translation_report.md]
#
# 退出码:0=成功(即使个别文件缺失,报告会标注缺失)
import argparse
import json
import os
import sys
from datetime import datetime, timezone


def read_text(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read()
    except OSError:
        return None


def count_lines(text):
    if text is None:
        return None
    return sum(1 for ln in text.splitlines() if ln.strip())


def probe_video(vid_dir):
    video = next(
        (f for f in sorted(os.listdir(vid_dir)) if f.startswith("video.") and not f.endswith(".part")),
        None,
    )
    return video


def gen_report(vid_dir):
    work = os.path.join(vid_dir, "work")
    out = []
    a = out.append

    a("# 翻译交付报告")
    a("")
    a("> 本报告由 tools/report.py 自动生成,生成时间(UTC): " + datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"))
    a("")

    # 1. 任务参数
    state = read_text(os.path.join(work, "session_state.json"))
    a("## 任务参数")
    if state:
        try:
            s = json.loads(state)
            a("")
            a(f"- URL: {s.get('url', '')}")
            a(f"- 工作区根: {s.get('workspace', '')}")
            a(f"- 视频目录 (VIDDIR): {s.get('vid_dir', '')}")
            p = s.get("params", {})
            a(f"- language: {p.get('language', '')} | whisper_model: {p.get('whisper_model', '')} | proxy: {p.get('proxy') or '(无)'} | domain_hint: {p.get('domain_hint') or '(空)'} | gpu: {p.get('gpu', '')} | burn: {'开' if p.get('burn_enabled') else '关'}")
            a(f"- 已完成阶段: {', '.join(s.get('stages_completed', [])) or '(无)'}")
        except Exception as e:
            a(f"- (session_state.json 解析失败: {e})")
    else:
        a("- (session_state.json 缺失)")
    a("")

    # 2. 视频信息
    info = read_text(os.path.join(vid_dir, "info.txt"))
    a("## 视频信息")
    if info:
        a("")
        for ln in info.strip().splitlines():
            a(f"- {ln}")
    else:
        a("- (info.txt 缺失)")
    a("")

    # 3. 交付物与阶段产物
    a("## 交付物(VIDDIR 根)")
    a("")
    deliverables = []
    video = probe_video(vid_dir)
    for name, desc in [
        (video, f"源视频 {video}"),
        ("video.burned.mp4", "烧录视频(可选)"),
        ("thumbnail.png", "封面"),
        ("info.txt", "元信息"),
        ("translation_report.md", "本报告"),
    ]:
        if name:
            p = os.path.join(vid_dir, name)
            sz = os.path.getsize(p) if os.path.isfile(p) else None
            deliverables.append(f"- {desc}: {'✓' if sz is not None else '✗'}{f' ({sz/1e6:.1f}MB)' if sz is not None else ''}")
    a("\n".join(deliverables))
    a("")

    a("## 中间产物与状态(VIDDIR/work)")
    a("")
    work_files = [
        "subtitle.srt", "source_merge.log", "translated_title.txt", "translated_lines.txt",
        "translated_subtitle.srt", "selfcheck.log", "review.log",
        "term_consistency_table.txt", "meta_translation_rules.txt", "synopsis_memory.txt", "ad_memory.txt",
        "audio.wav", "preflight.log", "session_state.json", "run.log", "issues.log",
    ]
    rows = []
    for f in work_files:
        p = os.path.join(work, f)
        if os.path.isfile(p):
            sz = os.path.getsize(p)
            rows.append(f"- {f}: ✓ ({sz/1024:.0f}KB)")
        else:
            rows.append(f"- {f}: ✗ (缺失)")
    a("\n".join(rows) if rows else "- (work/ 目录缺失)")
    a("")

    # 4. 过程记录(直接复用中间产物,不重复叙述)
    a("## 过程记录(直接复用中间产物)")
    a("")
    for f, label in [
        ("preflight.log", "环境预检 (preflight.log)"),
        ("source_merge.log", "源整理合并记录 (source_merge.log)"),
        ("selfcheck.log", "翻译自检记录 (selfcheck.log)"),
        ("review.log", "复核记录 (review.log)"),
    ]:
        txt = read_text(os.path.join(work, f))
        a(f"### {label}")
        a("")
        if txt and txt.strip():
            a("```")
            a(txt.strip())
            a("```")
        else:
            a("- (缺失或为空)")
        a("")

    # 4. 记忆文件摘要
    a("## 记忆文件摘要")
    a("")
    for f, label in [
        ("term_consistency_table.txt", "术语一致性表"),
        ("meta_translation_rules.txt", "元翻译规则"),
        ("ad_memory.txt", "广告概括"),
    ]:
        txt = read_text(os.path.join(work, f))
        n = count_lines(txt)
        a(f"- {label} ({f}): {n if n is not None else '缺失'} 条")
    syn = read_text(os.path.join(work, "synopsis_memory.txt"))
    if syn is not None:
        a(f"- 前情提要 (synopsis_memory.txt): {len(syn.strip())} 字")
        if syn.strip():
            a("")
            a("  > " + syn.strip().replace("\n", " "))
            a("")
    else:
        a("- 前情提要 (synopsis_memory.txt): 缺失")
    a("")

    # 5. 运行流水
    run = read_text(os.path.join(work, "run.log"))
    a("## 运行流水 (run.log)")
    a("")
    a("```")
    a(run.strip() if run else "(run.log 缺失)")
    a("```")
    a("")

    # 6. 已知问题
    issues = read_text(os.path.join(work, "issues.log"))
    a("## 已知问题 (issues.log)")
    a("")
    if issues and issues.strip():
        a("```")
        a(issues.strip())
        a("```")
    else:
        a("- 无记录。")
    a("")

    a("## 交付清单")
    a("")
    a("1. `translated_subtitle.srt`(VIDDIR/work/)— 最终字幕")
    a("2. `translated_title.txt`(VIDDIR/work/)+ `info.txt`(VIDDIR 根)")
    a("3. 记忆文件 4 个(VIDDIR/work/)")
    a("4. 本报告")
    a("5. 烧录产物 `video.burned.mp4`(如有)")
    a("6. 提示用户:审阅记忆文件与最终字幕;如有问题可要求局部重译。")
    a("")

    # 7. agent 补充区(可选)
    a("## agent 补充说明")
    a("")
    a("(agent 在此追加人工观察,如无则删除本段)")

    return "\n".join(out)


def main():
    parser = argparse.ArgumentParser(description="自动生成翻译交付报告")
    parser.add_argument("--vid-dir", required=True, help="VIDDIR 路径")
    parser.add_argument("--output", required=True, help="输出 markdown 路径")
    args = parser.parse_args()

    if not os.path.isdir(args.vid_dir):
        print(f"[report] FAIL 目录不存在: {args.vid_dir}")
        sys.exit(1)

    md = gen_report(args.vid_dir)
    with open(args.output, "w", encoding="utf-8") as f:
        f.write(md)
    print(f"[report] 报告已生成: {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
