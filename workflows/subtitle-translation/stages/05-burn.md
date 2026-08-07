# 阶段 05 — Burn 烧录(可选)

## 目标
将最终中文字幕烧录进视频,产出 `VIDDIR/video.burned.mp4`。

## 前置
- 04 通过;`VIDDIR/work/translated_subtitle.srt`(复核后版本)存在。
- 入参 `burn_enabled=true`;为 false 时本阶段**直接跳过**,在 run.log 写 `status=skipped`。

## 步骤

1. 确认最终字幕为 `VIDDIR/work/translated_subtitle.srt`(唯一交付字幕,无校对版)。
2. **核对 GPU 决定**(session_state.json 的 params.gpu):gpu=cpu → 用 `--gpu cpu`;gpu=auto/未记录 → 按 AGENTS.md「GPU 询问协议」先询问用户是否要 GPU 编码,再执行。
3. 执行烧录:
   ```bash
   tools/burn.sh --video VIDDIR/video.<ext> \
     --subtitle VIDDIR/work/translated_subtitle.srt \
     --output VIDDIR/video.burned.mp4 [--gpu auto|cpu|vaapi]
   ```
   - `--gpu auto`(默认):检测到 vaapi 硬件编码器则用 GPU,否则回退 CPU 并打印 WARN——**此时停下询问用户**是否接受 CPU 烧录。
   - `--gpu vaapi`:强制硬件编码,环境不支持时 FAIL,按失败处置表询问用户。
   - 可选参数: `--vaapi-device <dev>`(指定 render 设备)、`--encoder libx264`(CPU 时显式编码器)、`--enforce-source-bitrate`、`--min-bitrate-kbps N`。
4. 校验:
   ```bash
   ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 VIDDIR/video.burned.mp4
   ```
   时长应与原视频一致(±2 秒);不一致 → 记录并告知用户。
5. 更新 `VIDDIR/work/session_state.json`(stages_completed 追加 burn)+ `VIDDIR/work/run.log`。

## 产物(交付物在 VIDDIR 根)
- `video.burned.mp4`(已存在则自动跳过;字幕源为 VIDDIR/work/translated_subtitle.srt)

## 质量门槛
见 quality.md 阶段 05。

## 失败处置表

| 现象 | 处置(照表执行) |
|------|------------------|
| burn.sh 输出 WARN"未检测到可用 GPU 编码" | **停下询问用户**:是否接受 CPU 烧录?或修复 GPU 编码环境后重试;或跳过烧录(用户决定) |
| burn.sh exit 1(--gpu vaapi 环境不支持) | 照工具提示询问用户:降级 CPU 烧录 / 修复 GPU 环境 / 放弃烧录 |
| burn.sh exit 1(ffmpeg 失败) | 读 stderr:字幕路径含特殊字符(冒号/逗号/引号)→ 告知用户换工作区路径;编码参数问题 → 去掉显式参数重试;仍失败 → 走问题协议 |
| 字幕在视频中显示异常(乱码/位置错) | 中文 SRT 需 UTF-8 编码(工具已保证);视频无中文字体时烧录可能显示方块 → 告知用户系统字体问题,由用户决定是否继续 |
| 输出时长与原视频不一致 | 记录 issues.log,告知用户,由用户决定是否接受 |

> 禁止:自行修改 ffmpeg 参数做实验、自行换编码器(文档外参数需用户同意)。GPU 降级必须经用户确认,不得默默 CPU 烧录。
