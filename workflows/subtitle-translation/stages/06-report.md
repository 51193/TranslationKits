# 阶段 06 — Report 交付

## 目标

> **阶段导航**:上一阶段:[05 Burn](05-burn.md) | 下一阶段:[交付清单](../quality.md) → 审阅记忆文件与最终字幕
> 工作流总纲:[workflow.md](../workflow.md) | 工具清单:[tools.md](../tools.md) | 质量门槛:[quality.md](../quality.md)

自动生成交付报告 `translation_report.md`,向用户交付全部产物。

## 前置
- 05 通过(04 复核必过);`VIDDIR/work/` 内状态文件齐全。

## 步骤

1. 运行报告生成工具(样板全部自动生成,**不手写**):
   ```bash
   tools/report.py --vid-dir VIDDIR --output VIDDIR/translation_report.md
   ```
   工具用法见 [report.py](../tools.md#report)。
2. 核对:报告内容与 VIDDIR 实际状态一致(工具以文件系统为准);如有需要,在报告末尾「agent 补充说明」小节追加人工观察(如翻译质量抽查结论),追加内容保持简短。
3. **重复检查**:检查 `VIDDIR/work/run.log` 是否有重复 stage 行(同一 stage/status 多次记录),有则清理(保留一行)后重新运行 report.py;确认字幕/译文/报告无重复内容(见 AGENTS.md 铁律 4)。
4. **临时文件反馈**:检查 `/tmp/opencode/<视频名>/` 是否有残留,清理;在交付对话中向用户反馈本次临时文件使用情况(路径、用途、是否已清理);未使用则明说。
5. 按 quality.md「交付清单」向用户交付,提示:
   - VIDDIR 根 = 交付物(源视频/烧录视频/封面/info.txt/报告)
   - VIDDIR/work/ = 过程文件(字幕/译文/记忆/状态日志,供审阅与续跑)
6. 更新 `VIDDIR/work/session_state.json`(stages_completed 追加 report)+ `VIDDIR/work/run.log`。

## 产物
- 根:`translation_report.md`(自动生成)

## 质量门槛
见 [quality.md 阶段 06](../quality.md)。

## 失败处置表

| 现象 | 处置 |
|------|------|
| report.py exit 1 | 按输出处理(目录不存在→路径错误);work/ 状态文件缺失时,先重做对应阶段或走问题协议,不得手工编造报告内容 |
| 用户要求调整报告内容 | 反馈建议:报告结构是元指令的一部分,需经用户同意后修改 tools/report.py(遵循问题协议反馈) |
