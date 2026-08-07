# 阶段 04 — Burn 烧录(可选)

## 目标
将最终中文字幕烧录进视频,产出 `VIDDIR/video.burned.mp4`。

## 前置
- 03 通过;`translated_subtitle.srt` 存在。
- 入参 `burn_enabled=true`;为 false 时本阶段**直接跳过**,在 run.log 写 `status=skipped`。

## 步骤

1. 确认最终字幕为 `VIDDIR/translated_subtitle.srt`(唯一交付字幕,无校对版)。
2. 执行烧录:
   ```bash
   tools/burn.sh --video VIDDIR/video.<ext> \
     --subtitle VIDDIR/translated_subtitle.srt \
     --output VIDDIR/video.burned.mp4
   ```
   - 可选参数: `--encoder libx264`(显式编码器)、`--enforce-source-bitrate`(输出码率不低于原视频)、`--min-bitrate-kbps N`。
3. 校验:
   ```bash
   ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 VIDDIR/video.burned.mp4
   ```
   时长应与原视频一致(±2 秒);不一致 → 记录并告知用户。
4. 更新 `session_state.json`(stages_completed 追加 burn)+ `run.log`。

## 产物(VIDDIR 内)
- `video.burned.mp4`(已存在则自动跳过)

## 质量门槛
见 quality.md 阶段 04。

## 失败处置表

| 现象 | 处置(照表执行) |
|------|------------------|
| burn.sh exit 1(ffmpeg 失败) | 读 stderr:字幕路径含特殊字符(冒号/逗号/引号)→ 告知用户换工作区路径;编码参数问题 → 去掉显式参数重试;仍失败 → 走问题协议 |
| 字幕在视频中显示异常(乱码/位置错) | 中文 SRT 需 UTF-8 编码(工具已保证);视频无中文字体时烧录可能显示方块 → 告知用户系统字体问题,由用户决定是否继续 |
| 输出时长与原视频不一致 | 记录 issues.log,告知用户,由用户决定是否接受 |

> 禁止:自行修改 ffmpeg 参数做实验、自行换编码器(文档外参数需用户同意)。
