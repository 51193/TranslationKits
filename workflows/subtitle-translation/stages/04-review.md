# 阶段 04 — Review 复核(含全文校对)

## 目标
翻译全部完成后,站在**整个视频的全局视角**复核交付质量:全文校对字幕翻译、复核报告/状态/记忆等全部输出。**本阶段是翻译质量的最后一道关卡,必须在烧录(05)之前完成。**

> 与 03 的区别:03 的自检是翻译过程中的块级快查(selfcheck.log);本阶段是全文通读级校对 + 整体复核,能发现跨块问题(术语漂移、情节理解错误、遗漏广告段等)。

## 前置
- 03 通过;`VIDDIR/work/translated_subtitle.srt`、`translated_lines.txt` 与四个记忆文件存在。

## 步骤

### A. 全文校对(核心)
1. 通读 `VIDDIR/work/translated_subtitle.srt` **全部条目**,与 `VIDDIR/work/subtitle.srt`(源字幕)逐段对照,站在全片情节整体理解上检查。
2. 允许的修正(仅限):
   - 错译、漏译、明显不通顺的中文;
   - 术语不一致(与 `term_consistency_table.txt` 对齐;如术语表本身错了,先改术语表再改字幕);
   - 广告段遗留(漏译的广告、误写进记忆的广告内容);
   - 空文本条目、相邻语义重复条目(去重取前 start 后 end)。
3. 禁止:为风格/措辞润色、重排句子结构(除非明显错误)、改动时间轴(合并去重除外)、新增原文没有的信息。
4. 每次修正:**先在 `VIDDIR/work/review.log` 追加一行**记录(`[UTC时间] 修正: 条目N 原文=>译文 原因`),再编辑字幕文件。
5. **修正方式**:文本级修正(改译文内容)直接**用 Edit 工具编辑 `translated_subtitle.srt`**,禁止写脚本;涉及相邻条目合并(去重)时用 `tools/srt_tool.py merge`(注意:merge 会重排序号,需在日志中注明)。
6. 修正完成后:
   - `tools/srt_tool.py validate VIDDIR/work/translated_subtitle.srt`(必须 exit 0,空文本 WARN 清零);
   - 若文本有变化,同步 `translated_lines.txt`:`tools/srt_tool.py to-txt VIDDIR/work/translated_subtitle.srt VIDDIR/work/translated_lines.txt`。

### B. 整体复核
逐项检查并在 `VIDDIR/work/review.log` 记录结论:
1. **状态一致**:`session_state.json` 的 stages_completed 与 `run.log` 记录一致;无"已完成但文件缺失"的阶段。
2. **报告输入**:`preflight.log`、`selfcheck.log`、`source_merge.log`、`issues.log` 存在且内容与产物自洽。
3. **记忆文件**:术语表/元规则无广告残留;前情提要聚焦正片主线、无广告段;ad_memory 覆盖全部广告段。
4. **交付物**:VIDDIR 根层交付物齐全(源视频/封面/info.txt;烧录产物在 05 之后)。
5. 任何发现的问题:**能自行修正的立即修正并记录;不能的(如需要重跑 03 某块)记录后按 03 失败处置表处理,或走问题协议**。

### C. 收尾
- `VIDDIR/work/review.log` 末尾写结论行:`[UTC时间] 复核结论: 通过/有条件通过(说明)`。
- 更新 `VIDDIR/work/session_state.json`(stages_completed 追加 review)+ `VIDDIR/work/run.log`。

## 产物(VIDDIR/work/ 内)
- `review.log`(全文校对修正记录 + 整体复核结论)
- `translated_subtitle.srt`(复核修正后的最终字幕;若未修改则原样)
- `translated_lines.txt`(如字幕有变化则同步)

## 质量门槛
见 quality.md 阶段 04。

## 失败处置表

| 现象 | 处置 |
|------|------|
| 全文校对发现大量错译(>5% 条目) | 停止盲目逐条修补;记录 issues.log,告知用户:可能翻译策略/模型/提示词有问题,建议重跑 03(可缩小块大小或换模型,需用户同意),而非在校对中打补丁 |
| 发现漏译整段(块级遗漏) | 回 03 补译该块(按 03 失败处置表);补译后重新进入本阶段全文校对 |
| 记忆文件发现广告残留 | 按 memory.md 清理记忆文件;检查对应字幕是否受影响,一并修正 |
| validate 失败(修正引入结构错误) | 修复结构错误;无法修复 → 从修正前状态恢复(03 的 compose 可重建,条数不变时文本修正不改变结构) |
| 用户对复核结论有异议 | 记录 issues.log;按用户要求调整(如局部重译)后重跑本阶段 |
