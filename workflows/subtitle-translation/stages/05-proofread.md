# 阶段 05 — Proofread 校对

## 目标
最小修补:去重复读、清空空文本条目。产出最终字幕。**产物全部在 VIDDIR 内**。

## 前置
- 04 通过;`VIDDIR/translated_subtitle.srt` 存在。

## 步骤

1. 复制为校对版本:
   ```bash
   cp VIDDIR/translated_subtitle.srt VIDDIR/translated_subtitle.proofread.srt
   ```
2. 按 prompts/proofread.md 以窗口逐对扫描全部条目:
   - 语义重复 → 合并去重(前 start、后 end,取前条文本)。
   - 空文本条目 → 并入相邻条目或删除。
3. 校验(必须无警告,空文本清零):
   ```bash
   tools/srt_tool.py validate VIDDIR/translated_subtitle.proofread.srt
   ```
4. 导出最终纯文本:`tools/srt_tool.py to-txt VIDDIR/translated_subtitle.proofread.srt VIDDIR/raw_translated_subtitle.txt`(覆盖 04 版本)。
5. 更新 `session_state.json` + `run.log`。

## 产物(VIDDIR 内)
- `translated_subtitle.proofread.srt`(最终交付字幕)
- `raw_translated_subtitle.txt`(最终纯文本)

## 质量门槛
见 quality.md 阶段 05。

## 失败处置表

| 现象 | 处置 |
|------|------|
| validate 仍有空文本 | 继续修补直至清零;无法清零 → 记录 issues.log 并告知用户 |
| 校对改动过大(>5% 条目) | 停下检查:是否把翻译质量问题误当校对问题;是 → 回 04 修正翻译,校对只留最小修补 |
| 发现翻译阶段遗留的错译/漏译 | 不得在校对阶段重译;记录 issues.log,告知用户,回 04 修复(需用户确认范围) |
