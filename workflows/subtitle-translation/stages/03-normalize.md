# 阶段 03 — Normalize 规范化

## 目标
修复被语法性错误切断的句子(相邻条合并),得到结构干净、语义完整的源字幕。

## 前置
- 02 通过;`subtitle.srt` 与 `raw_subtitle.txt` 存在。

## 步骤

1. 复制为规范化版本(保留原件):
   ```bash
   cp <workspace>/subtitle.srt <workspace>/subtitle.normalized.srt
   ```
2. 按 prompts/normalize.md 逐对扫描 `raw_subtitle.txt`,得出合并建议表。
3. 编辑 `subtitle.normalized.srt` 实施合并(取前条 start、后条 end,文本拼接为一句,序号重排)。
4. 校验:
   ```bash
   tools/srt_tool.py validate <workspace>/subtitle.normalized.srt
   ```
5. 重导出纯文本供翻译阶段使用:
   ```bash
   tools/srt_tool.py to-txt <workspace>/subtitle.normalized.srt <workspace>/raw_subtitle.normalized.txt
   ```
6. 更新 `session_state.json` + `run.log`。

## 产物
- `subtitle.normalized.srt`、`raw_subtitle.normalized.txt`

## 质量门槛
见 quality.md 阶段 03。

## 自检要点
- 只做合并,不做拆分/新增/改写。
- 合并量克制:默认不合并;合并数超过原条数 30% 时停下,走问题协议(向用户报告转写可能断句过碎)。
- 编辑后逐条确认序号连续、时间轴单调。

## 失败处置表

| 现象 | 处置 |
|------|------|
| validate 报序号/时间轴错误 | 手工修复对应条目(属正常编辑工作),重新 validate |
| 合并后出现空文本条目 | 将空文本并入相邻条目(与校对同规则) |
| 原字幕本身质量差(断句严重破碎) | 记录 issues.log;告知用户,可建议换 whisper 模型重转写(需用户同意)或继续(用户决定) |

> 规范化是语义判断,你(agent)的判断即流程的"模型"。但结构错误由 validate 兜底。
