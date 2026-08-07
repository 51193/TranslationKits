# 阶段 02 — Transcribe 转写

## 目标

> **阶段导航**:上一阶段:[01 Fetch](01-fetch.md) | 下一阶段:[03 Translate](03-translate.md)
> 工作流总纲:[workflow.md](../workflow.md) | 工具清单:[tools.md](../tools.md) | 质量门槛:[quality.md](../quality.md)

从视频抽取音频,whisper 转写为句级时间戳字幕。**全部产物写入 VIDDIR**。

## 前置
- 01 通过;`VIDDIR/video.<ext>` 与 `VIDDIR/info.txt` 存在(扩展名读 info.txt「扩展名」行)。

## 步骤

1. 抽取音频(照抄本命令,不要改写):
   ```bash
   ffmpeg -y -i VIDDIR/video.<ext> -vn -acodec pcm_s16le -ar 44100 VIDDIR/work/audio.wav
   ```
2. 转写(语言/模型取 params;设备自动探测,见下):
   ```bash
   tools/transcribe.py VIDDIR/work/audio.wav --output VIDDIR/work/subtitle.srt \
     --model <whisper_model> --language <language> [--device auto]
   ```
   - **GPU 自动探测**:脚本会逐个尝试可用 GPU(小矩阵试跑),自动跳过不可用设备(如驱动不兼容的独显),全不可用则 CPU。无需手动指定;转写日志会打印"使用 GPU[N] / 回退 CPU"。
   - 输出已存在且较新会自动跳过。
3. 结构校验:
   ```bash
   tools/srt_tool.py validate VIDDIR/work/subtitle.srt
   ```
4. 更新 `VIDDIR/work/session_state.json` + `VIDDIR/work/run.log`(run.log 注明转写所用设备:`GPU[N] <名称>` 或 `CPU`)。

## 产物(VIDDIR 内)
- work/:`audio.wav`、`subtitle.srt`

## 质量门槛
见 [quality.md 阶段 02](../quality.md)(validate 无错误;validate 用法见 [tools.md#validate](../tools.md#validate))。

## 失败处置表

| 现象 | 处置(照表执行) |
|------|------------------|
| ffmpeg 失败 | 检查 `VIDDIR/video.*` 是否存在且非空;损坏则重新 fetch(需用户同意);ffmpeg 本身错误 → 走问题协议 |
| 转写日志显示"回退 CPU"/"所有 GPU 均不可用" | **停下核对 GPU 决定**(session_state.json 的 params.gpu):gpu=cpu(用户已确认)→ 继续并说明;gpu=auto 或未记录 → 按 AGENTS.md「GPU 询问协议」询问用户(是否修复 GPU 或用 CPU 继续),决定后更新 params.gpu 再继续 |
| transcribe.py exit 1,缺模型文件或网络下载模型失败 | 模型下载需网络;请求代理或确认网络后重试;仍失败 → 走问题协议 |
| 转写语言明显不对(如英文视频输出中文) | 确认 params.language;修正后加 `--force` 重跑(属文档允许操作,告知用户) |
| validate 有错误(序号/时间轴) | 重跑转写(`--force`);仍错误 → 走问题协议 |
| validate 有警告(重叠/间隙) | 记录;whisper 原生特性,合理范围内放行;警告数量异常(>10%)→ 告知用户 |

> 禁止:自行换转写引擎、自行安装额外依赖、自行调 whisper 参数做实验、把产物写到 VIDDIR 以外。
> 说明:GPU 探测与自动回退是工具行为;但**是否接受 CPU 是用户决定**,不得默默降级——见 AGENTS.md「GPU 询问协议」。
