# 阶段 04 — Translate 翻译(核心)

## 目标
把规范化源字幕逐句翻译为中文,并维护四个记忆文件,产出 `translated_subtitle.srt`。**全部产物与记忆文件在 VIDDIR 内**。

## 前置
- 03 通过;`VIDDIR/subtitle.normalized.srt` 存在。
- 已与用户确认 `domain_hint`(可为空)。

## 步骤

1. **翻译标题**:按 prompts/title.md 翻译,写入 `VIDDIR/translated_title.txt`(已存在则跳过)。
2. **读记忆**:读 VIDDIR 内四个记忆文件(不存在视为"尚无")。
3. **分块翻译**:按 prompts/translate-module.md 逐块执行:
   - 块大小自定:短视频一次全量,长视频 20~40 句/块;上一块译完、记忆更新后再译下一块。
   - 每块:注入记忆文件与上文译文 → 请求模型输出 JSON → 校验行数 → 提取译文 → 按 memory.md 更新记忆文件。
   - 译文逐行写入 `VIDDIR/translated_lines.txt`(整文件重写,行号与源字幕一一对应)。
4. **生成字幕**(行数不匹配会失败,失败即本块翻译不守恒,回改):
   ```bash
   tools/srt_tool.py from-txt --source VIDDIR/subtitle.normalized.srt \
     --text VIDDIR/translated_lines.txt --output VIDDIR/translated_subtitle.srt
   ```
5. **校验**:`tools/srt_tool.py validate VIDDIR/translated_subtitle.srt`。
6. **自检**:执行 quality.md「翻译自检清单」全部 5 项(逐块复查、术语一致性、广告检查、行数守恒、全文终检)。
7. 导出交付文本:`tools/srt_tool.py to-txt VIDDIR/translated_subtitle.srt VIDDIR/raw_translated_subtitle.txt`。
8. 更新 `session_state.json` + `run.log`。

## 产物(全部在 VIDDIR 内)
- `translated_title.txt`、`translated_lines.txt`、`translated_subtitle.srt`、`raw_translated_subtitle.txt`
- 四个记忆文件(如内容有更新)

## 质量门槛
见 quality.md 阶段 04(自检清单 5 项全部执行,全部通过)。

## 失败处置表

| 现象 | 处置 |
|------|------|
| 模型输出 JSON 解析失败/行数不符 | 携带错误信息重试 1~2 次;仍失败 → 块大小减半重试;同一块失败 3 次 → 记录 issues.log,告知用户(可能记忆文件或提示词有缺陷),停止并等待指示 |
| from-txt 报行数不匹配 | 定位是哪个块导致(与源字幕逐行对拍),修正该块译文行数后重跑 from-txt |
| 漏译/错位(自检发现) | 单句修复:对缺句单独补译,整块回改重写;修复后重跑 from-txt + validate |
| 术语漂移(自检发现) | 按记忆文件统一译文,回改涉及块;更新术语表 |
| 广告段内容渗入记忆文件 | 从记忆文件移除广告条目,回改涉及块的记忆更新;确认 ad-policy.md 遵守 |
| 上下文过长/模型能力不足导致质量下降 | 缩小块大小;必要时向用户建议更长上下文的模型(需用户同意更换) |

## 续跑注意
- 工作区即状态:记忆文件 + `translated_lines.txt` + session_state.json 可随时恢复(均在 VIDDIR 内)。
- 中断后重开:校验已完成的块(记忆文件与译文块数是否自洽),从第一个未完成块继续。
