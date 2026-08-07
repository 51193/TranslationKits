#!/usr/bin/env python3
# 转写阶段:音频 -> 句级时间戳 SRT(whisper)。
# 用法:
#   tools/transcribe.py <audio> --output <out.srt> --model <model> --language <lang> [--device auto|cpu|cuda] [--force]
#
# 说明:
#   - device=auto 时自动检测 CUDA/ROCm 可用性,否则回退 CPU;
#   - 输出已存在且不早于音频时跳过(除非 --force);
#   - 语言留空表示自动检测。
import argparse
import os
import sys
from datetime import timedelta
from pathlib import Path

_venv_py = Path(__file__).resolve().parent.parent / ".venv" / "bin" / "python3"
if _venv_py.is_file() and sys.executable != str(_venv_py):
    os.execv(str(_venv_py), [str(_venv_py), __file__] + sys.argv[1:])

import srt


def detect_device(requested: str):
    if requested and requested != "auto":
        return requested

    try:
        import torch
        if torch.cuda.is_available():
            for i in range(torch.cuda.device_count()):
                name = torch.cuda.get_device_name(i)
                # 跳过名字明显是 CPU 的设备(ROCm 设备名读取 bug 的场景);此类设备
                # 一旦执行 kernel 会直接段错误,且段错误无法被 try/except 捕获。
                if "processor" in name.lower() or " cpu " in f" {name.lower()} ":
                    print(f"[transcribe] GPU[{i}] {name} 疑似非 GPU 设备,跳过")
                    continue
                try:
                    probe = torch.randn(16, device=f"cuda:{i}")
                    torch.cuda.synchronize()
                    del probe
                    print(f"[transcribe] 使用 GPU[{i}]: {name}")
                    return f"cuda:{i}"
                except Exception as e:
                    print(f"[transcribe] GPU[{i}] {name} 不可用({type(e).__name__}),跳过")
            print("[transcribe] 所有 GPU 均不可用,回退 CPU")
            return "cpu"
    except Exception:
        pass

    print("[transcribe] 未检测到可用 GPU,回退到 CPU")
    return "cpu"


def transcribe(audio_path, output_srt, model_name="turbo", language=None, device="auto", force=False):
    output_path = Path(output_srt)
    audio_p = Path(audio_path)

    if not force and output_path.exists() and output_path.stat().st_mtime > audio_p.stat().st_mtime:
        print(f"[transcribe] 输出已存在且较新,跳过: {output_srt}")
        return

    import whisper

    resolved_device = detect_device(device)
    use_fp16 = resolved_device == "cuda"

    print(f"[transcribe] 加载模型: {model_name}(设备: {resolved_device})...")
    model = whisper.load_model(model_name, device=resolved_device)

    print(f"[transcribe] 开始转写: {audio_path}")
    result = model.transcribe(
        audio_path,
        language=language or None,
        fp16=use_fp16,
        verbose=True,
        word_timestamps=False,
    )

    subtitles = []
    for i, segment in enumerate(result["segments"]):
        text = segment.get("text", "").strip()
        if not text:
            continue
        start = timedelta(seconds=round(segment["start"], 3))
        end = timedelta(seconds=round(segment["end"], 3))
        subtitles.append(srt.Subtitle(index=i + 1, start=start, end=end, content=text))

    with open(output_srt, "w", encoding="utf-8") as f:
        f.write(srt.compose(subtitles))

    print(f"[transcribe] 句级 SRT 已生成({len(subtitles)} 条): {output_srt}")


def main():
    parser = argparse.ArgumentParser(description="Whisper 音频 -> 句级时间戳 SRT")
    parser.add_argument("audio", help="输入音频文件路径")
    parser.add_argument("--output", required=True, help="输出 SRT 路径")
    parser.add_argument("--model", default="turbo", help="模型: tiny/base/small/medium/large/large-v3/turbo")
    parser.add_argument("--language", default="en", help="语言代码: zh/en/ja 等,留空=自动检测")
    parser.add_argument("--device", default="auto", help="计算设备: auto/cpu/cuda/cuda:1 等(HIP_VISIBLE_DEVICES 优先于此处)")
    parser.add_argument("--force", action="store_true", help="强制重新转写,忽略缓存")

    args = parser.parse_args()

    if not os.path.exists(args.audio):
        print(f"[transcribe] FAIL 音频文件不存在: {args.audio}")
        sys.exit(1)

    transcribe(
        audio_path=args.audio,
        output_srt=args.output,
        model_name=args.model,
        language=args.language.strip() or None,
        device=args.device,
        force=args.force,
    )


if __name__ == "__main__":
    main()
