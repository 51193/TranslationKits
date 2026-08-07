#!/usr/bin/env python3
# SRT 结构工具:校验 / 转纯文本 / 由纯文本重建 SRT / 合并 / 拆块 / 拼块 / 统计。
# 供工作流各阶段验证产物与执行格式转换,是结构正确性的唯一权威。
# 03 源整理与分块翻译必须使用本工具(merge/split/compose),禁止手算序号或手写脚本。
#
# 子命令:
#   validate   <file.srt>                 校验格式、序号、时间轴;0=通过 1=错误 2=警告
#   to-txt     <file.srt> <out.txt>       每条字幕文本一行(无序号/时间轴)
#   from-txt   --source <file.srt> --text <in.txt> --output <out.srt>
#                                        用源 SRT 的时间轴重建 SRT,文本逐行替换;
#                                        行数与源条数不一致时失败(exit 1)
#   merge      <file.srt> --from N-M [--from ...] --output <out.srt> [--log <log>]
#                                        合并指定范围的条目(取前条 start、后条 end,
#                                        文本按序拼接),自动序号重排;--log 输出合并日志
#   split      <file.srt> --out-dir <dir> [--size N]
#                                        按 N 条/块拆分为 block_0001.srt...,
#                                        并生成 manifest.txt(块文件与行范围映射);
#                                        --size 0 表示单块
#   compose    --source <file.srt> --blocks-dir <dir> --output <out.srt> [--lines <out.txt>]
#                                        按 manifest 顺序拼接块译文 translated_0001.txt,
#                                        行数必须与源条数一致(缺块/多行即失败);
#                                        生成 SRT(时间轴取自源)与译文纯文本
#   stats      <file.srt>                 条目数、总时长、文本长度统计
#
# 用法示例:
#   tools/srt_tool.py validate translated_subtitle.srt
#   tools/srt_tool.py merge work/subtitle.srt --from 20-21 --from 57-58 --output work/subtitle.srt --log work/source_merge.log
#   tools/srt_tool.py split work/subtitle.srt --out-dir work/blocks --size 30
#   tools/srt_tool.py compose --source work/subtitle.srt --blocks-dir work/blocks --output work/translated_subtitle.srt --lines work/translated_lines.txt
import argparse
import os
import re
import sys
from datetime import timedelta
from pathlib import Path

_venv_py = Path(__file__).resolve().parent.parent / ".venv" / "bin" / "python3"
if _venv_py.is_file() and sys.executable != str(_venv_py):
    os.execv(str(_venv_py), [str(_venv_py), __file__] + sys.argv[1:])

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


def cmd_merge(args):
    subs = read_srt(args.file)

    ranges = []
    for spec in args.from_ranges:
        if "-" in spec:
            a, b = spec.split("-", 1)
            try:
                a, b = int(a), int(b)
            except ValueError:
                print(f"[merge] FAIL 无法解析范围: {spec}")
                return 1
        else:
            try:
                a = b = int(spec)
            except ValueError:
                print(f"[merge] FAIL 无法解析范围: {spec}")
                return 1
        ranges.append((a, b))

    prev_end = 0
    for a, b in ranges:
        if a < 1 or b > len(subs) or a > b:
            print(f"[merge] FAIL 范围越界: {a}-{b}(源共 {len(subs)} 条)")
            return 1
        if a <= prev_end:
            print(f"[merge] FAIL 范围重叠或乱序: {a}-{b}(应互不重叠且按序给出)")
            return 1
        prev_end = b

    merged = []
    log_lines = []
    i = 0
    while i < len(subs):
        rng = next((r for r in ranges if r[0] <= i + 1 <= r[1]), None)
        if rng is None:
            merged.append(subs[i])
            i += 1
        else:
            a, b = rng
            group = subs[a - 1 : b]
            text = " ".join(
                (s.content or "").strip() for s in group if (s.content or "").strip()
            )
            merged.append(srt.Subtitle(index=0, start=group[0].start, end=group[-1].end, content=text))
            log_lines.append(f"{a}-{b} => {text}")
            i = b

    for idx, s in enumerate(merged, 1):
        s.index = idx
    write_srt(args.output, merged)

    if args.log:
        with open(args.log, "w", encoding="utf-8") as f:
            f.write("\n".join(log_lines) + "\n" if log_lines else "")

    print(
        f"[merge] 合并 {len(log_lines)} 处({len(subs)} -> {len(merged)} 条),序号已重排: {args.output}"
    )
    if args.log:
        print(f"[merge] 合并日志: {args.log}")
    return 0


def cmd_split(args):
    subs = read_srt(args.file)
    if not subs:
        print(f"[split] FAIL 文件为空: {args.file}")
        return 1
    size = args.size if args.size and args.size > 0 else len(subs)
    os.makedirs(args.out_dir, exist_ok=True)

    manifest = []
    for bi, start in enumerate(range(0, len(subs), size), 1):
        chunk = subs[start : start + size]
        name = f"block_{bi:04d}.srt"
        write_srt(os.path.join(args.out_dir, name), chunk)
        manifest.append(f"{name} {start + 1}-{start + len(chunk)}")

    with open(os.path.join(args.out_dir, "manifest.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(manifest) + "\n")

    print(
        f"[split] 拆分为 {len(manifest)} 块({len(subs)} 条,{size} 条/块): {args.out_dir}"
    )
    return 0


def cmd_compose(args):
    subs = read_srt(args.source)
    manifest_path = os.path.join(args.blocks_dir, "manifest.txt")
    if not os.path.isfile(manifest_path):
        print(f"[compose] FAIL 缺少 manifest.txt: {manifest_path}(先运行 split)")
        return 1

    blocks = []
    for ln in open(manifest_path, encoding="utf-8").read().splitlines():
        ln = ln.strip()
        if not ln:
            continue
        parts = ln.split()
        if len(parts) != 2:
            print(f"[compose] FAIL manifest 行格式错误: {ln}")
            return 1
        name, rng = parts
        a, b = map(int, rng.split("-"))
        blocks.append((name, a, b))

    lines = []
    missing = []
    for name, a, b in blocks:
        tname = name.replace("block_", "translated_").replace(".srt", ".txt")
        tpath = os.path.join(args.blocks_dir, tname)
        if not os.path.isfile(tpath):
            missing.append(tname)
            continue
        with open(tpath, encoding="utf-8") as f:
            tlines = [ln.rstrip("\n").rstrip("\r") for ln in f]
        if len(tlines) != b - a + 1:
            print(
                f"[compose] FAIL 块 {tname} 行数错误: 期望 {b - a + 1} 行(源条目 {a}-{b}),"
                f"实际 {len(tlines)} 行。请修正该块译文后重试。"
            )
            return 1
        lines.extend(tlines)

    if missing:
        print(f"[compose] FAIL 缺少块译文: {', '.join(missing)}")
        return 1

    out = []
    for i, (sub, line) in enumerate(zip(subs, lines), start=1):
        out.append(srt.Subtitle(index=i, start=sub.start, end=sub.end, content=line.strip()))
    write_srt(args.output, out)

    if args.lines:
        with open(args.lines, "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")

    print(
        f"[compose] 拼接 {len(blocks)} 块译文,共 {len(lines)} 条(与源一致): {args.output}"
    )
    if args.lines:
        print(f"[compose] 译文纯文本: {args.lines}")
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

    p_m = sub.add_parser("merge", help="合并条目 + 序号重排")
    p_m.add_argument("file")
    p_m.add_argument("--from", dest="from_ranges", action="append", required=True,
                     help="合并范围,可多次: N 或 N-M")
    p_m.add_argument("--output", required=True)
    p_m.add_argument("--log", default=None, help="合并日志输出路径(每行: 原句号范围 => 合并后文本)")

    p_sp = sub.add_parser("split", help="拆分为块")
    p_sp.add_argument("file")
    p_sp.add_argument("--out-dir", required=True)
    p_sp.add_argument("--size", type=int, default=0, help="每块条数;0=单块")

    p_c = sub.add_parser("compose", help="块译文 -> SRT")
    p_c.add_argument("--source", required=True)
    p_c.add_argument("--blocks-dir", required=True)
    p_c.add_argument("--output", required=True)
    p_c.add_argument("--lines", default=None, help="输出译文纯文本路径")

    p_s = sub.add_parser("stats", help="统计")
    p_s.add_argument("file")

    args = parser.parse_args()
    rc = {"validate": cmd_validate, "to-txt": cmd_to_txt, "from-txt": cmd_from_txt, "merge": cmd_merge, "split": cmd_split, "compose": cmd_compose, "stats": cmd_stats}[args.cmd](args)
    sys.exit(rc)


if __name__ == "__main__":
    main()
