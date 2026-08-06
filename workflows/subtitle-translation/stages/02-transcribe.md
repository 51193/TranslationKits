# 阶段 02 — Transcribe 转写

## 目标
从视频抽取音频,whisper 转写为句级时间戳字幕,并导出纯文本。**全部产物写入 VIDDIR**。

## 前置
- 01 通过;`VIDDIR/video.<ext>` 与 `VIDDIR/info.txt` 存在(扩展名读 info.txt「扩展名」行)。

## 步骤

1. 抽取音频(照抄本命令,不要改写):
   ```bash
   ffmpeg -y -i VIDDIR/video.<ext> -vn -acodec pcm_s16le -ar 44100 VIDDIR/audio.wav
   ```
2. 转写(语言/模型取 params):
   ```bash
   tools/transcribe.py VIDDIR/audio.wav --output VIDDIR/subtitle.srt \
     --model <whisper_model> --language <language> [--device auto]
   ```
   - 设备自动检测:有 CUDA/ROCm 用 GPU,否则 CPU(脚本内置,无需干预)。
   - 输出已存在且较新会自动跳过。
3. 导出纯文本:
   ```bash
   tools/srt_tool.py to-txt VIDDIR/subtitle.srt VIDDIR/raw_subtitle.txt
   ```
4. 结构校验:
   ```bash
   tools/srt_tool.py validate VIDDIR/subtitle.srt
   ```
5. 行数比对:`wc -l VIDDIR/raw_subtitle.txt` 应等于 validate 输出的条目数。
6. 更新 `session_state.json` + `run.log`。

## 产物(VIDDIR 内)
- `audio.wav`、`subtitle.srt`、`raw_subtitle.txt`

## 质量门槛
见 quality.md 阶段 02(validate 无错误、行数一致)。

## 失败处置表

| 现象 | 处置(照表执行) |
|------|------------------|
| ffmpeg 失败 | 检查 `VIDDIR/video.*` 是否存在且非空;损坏则重新 fetch(需用户同意);ffmpeg 本身错误 → 走问题协议 |
| transcribe.py exit 1,错误含 CUDA/显存(OOM) | 记录;用 CPU 重试一次(`--device cpu`),告知用户将明显变慢;成功则继续,仍失败 → 走问题协议 |
| transcribe.py exit 1,缺模型文件或网络下载模型失败 | 模型下载需网络;请求代理或确认网络后重试;仍失败 → 走问题协议 |
| 转写语言明显不对(如英文视频输出中文) | 确认 params.language;修正后加 `--force` 重跑(属文档允许操作,告知用户) |
| validate 有错误(序号/时间轴) | 重跑转写(`--force`);仍错误 → 走问题协议 |
| validate 有警告(重叠/间隙) | 记录;whisper 原生特性,合理范围内放行;警告数量异常(>10%)→ 告知用户 |

> 禁止:自行换转写引擎、自行安装额外依赖、自行调 whisper 参数做实验、把产物写到 VIDDIR 以外。
