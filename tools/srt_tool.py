#!/usr/bin/env python3
# SRT 结构工具:校验 / 转纯文本 / 由纯文本重建 SRT / 统计。
# 供工作流各阶段验证产物与执行格式转换,是结构正确性的唯一权威。
#
# 子命令:
#   validate   <file.srt>                 校验格式、序号、时间轴;0=通过 1=错误 2=警告
#   to-txt     <file.srt> <out.txt>       每条字幕文本一行(无序号/时间轴)
#   from-txt   --source <file.srt> --text <in.txt> --output <out.srt>
#                                        用源 SRT 的时间轴重建 SRT,文本逐行替换;
#                                        行数与源条数不一致时失败(exit 1)
#   stats      <file.srt>                 条目数、总时长、文本长度统计
#
# 用法示例:
#   tools/srt_tool.py to-txt subtitle.srt raw_subtitle.txt
#   tools/srt_tool.py from-txt --source subtitle.srt --text translated_lines.txt --output translated_subtitle.srt
#   tools/srt_tool.py validate translated_subtitle.srt
import argparse
import sys
from datetime import timedelta

import srt


def read_srt(path):
    with open(path, "r", encoding="utf-8-sig") as f:
        return list(srt.parse(f.read()))


def write_srt(path, subs):
    with open(path, "w", encoding="utf-8") as f:
        f.write(srt.compose(subs))


def cmd_validate(args):
    try:
        subs = read_srt(args.file)
    except Exception as e:
        print(f"[validate] FAIL 无法解析 SRT: {e}")
        return 1

    if not subs:
        print("[validate] FAIL 文件中没有字幕条目")
        return 1

    errors = []
    warns = []
    prev_end = None
    for i, sub in enumerate(subs):
        idx = i + 1
        if sub.index != idx:
            errors.append(f"第 {i + 1} 条序号应为 {idx},实际为 {sub.index}")
        if sub.start > sub.end:
            errors.append(f"第 {idx} 条时间轴非法: start={sub.start} > end={sub.end}")
        if prev_end is not None and sub.start < prev_end:
            warns.append(f"第 {idx} 条与上一条时间轴重叠: start={sub.start} < prev_end={prev_end}")
        if prev_end is not None and sub.start > prev_end + timedelta(seconds=0.5):
            warns.append(f"第 {idx} 条与上一条存在较大间隙(可能漏句): gap={sub.start - prev_end}")
        if not (sub.content or "").strip():
            warns.append(f"第 {idx} 条文本为空")
        prev_end = sub.end

    for e in errors:
        print(f"[validate] ERROR {e}")
    for w in warns:
        print(f"[validate] WARN  {w}")

    total = subs[-1].end - subs[0].start
    print(f"[validate] 条目数: {len(subs)}  总时长: {total}  错误: {len(errors)}  警告: {len(warns)}")
    if errors:
        return 1
    if warns:
        return 2
    print("[validate] OK")
    return 0


def cmd_to_txt(args):
    subs = read_srt(args.file)
    with open(args.out, "w", encoding="utf-8") as f:
        for sub in subs:
            f.write((sub.content or "").strip() + "\n")
    print(f"[to-txt] 写出 {len(subs)} 行文本: {args.out}")
    return 0


def cmd_from_txt(args):
    subs = read_srt(args.source)
    with open(args.text, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n").rstrip("\r") for line in f]

    if len(lines) != len(subs):
        print(
            f"[from-txt] FAIL 行数不匹配: 源 SRT 有 {len(subs)} 条字幕,文本文件有 {len(lines)} 行。"
            f"请修正文本行数后重试(不允许合并或拆分)。"
        )
        return 1

    out = []
    for i, (sub, line) in enumerate(zip(subs, lines), start=1):
        out.append(srt.Subtitle(index=i, start=sub.start, end=sub.end, content=line.strip()))
    write_srt(args.output, out)
    print(f"[from-txt] 写出 {len(out)} 条字幕(时间轴取自 {args.source}): {args.output}")
    return 0


def cmd_stats(args):
    subs = read_srt(args.file)
    if not subs:
        print(f"[stats] 文件为空: {args.file}")
        return 0
    total = subs[-1].end - subs[0].start
    lengths = [len((s.content or "").strip()) for s in subs]
    print(f"[stats] 文件: {args.file}")
    print(f"[stats] 条目数: {len(subs)}")
    print(f"[stats] 总时长: {total}")
    print(f"[stats] 文本长度: 平均 {sum(lengths) / len(lengths):.1f} 字符,最短 {min(lengths)},最长 {max(lengths)}")
    return 0


def main():
    parser = argparse.ArgumentParser(description="SRT 结构工具")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_v = sub.add_parser("validate", help="校验 SRT")
    p_v.add_argument("file")

    p_t = sub.add_parser("to-txt", help="SRT -> 纯文本")
    p_t.add_argument("file")
    p_t.add_argument("out")

    p_f = sub.add_parser("from-txt", help="纯文本 + 源时间轴 -> SRT")
    p_f.add_argument("--source", required=True)
    p_f.add_argument("--text", required=True)
    p_f.add_argument("--output", required=True)

    p_s = sub.add_parser("stats", help="统计")
    p_s.add_argument("file")

    args = parser.parse_args()
    rc = {"validate": cmd_validate, "to-txt": cmd_to_txt, "from-txt": cmd_from_txt, "stats": cmd_stats}[args.cmd](args)
    sys.exit(rc)


if __name__ == "__main__":
    main()
