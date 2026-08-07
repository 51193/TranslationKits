# 源字幕整理提示词片段(03 翻译阶段 A 子步骤)

> 使用位置:[03 阶段 A 源整理](../stages/03-translate.md) | 执行工具:[merge](../tools.md#merge)

## 任务
判断相邻两条字幕是否应该合并成一句,修复被语法性错误切断的句子。

## 判定原则
- 默认不合并。
- 只有在语法/句法被明显错误切断时才合并(如 "Because..." 被切断的下半句)。
- 宁可不合并,也不要形成大段长句。

## 约束
- 仅用于修复语法断裂。
- 不得改写原意,不得扩写,不得为流畅性重写。
- 不得拆分、不得新增字幕条目。

## 执行方式(agent)
- 通读 `VIDDIR/work/subtitle.srt` 全部条目,逐对扫描相邻句。
- 得出**合并清单**:每行 `N-M`(第 N 到 M 条合并为一条),默认不合并。
- **禁止手算序号、禁止写脚本**:执行合并一律用工具:
  ```bash
  tools/srt_tool.py merge VIDDIR/work/subtitle.srt --from N-M [--from N2-M2 ...] \
    --output VIDDIR/work/subtitle.srt --log VIDDIR/work/source_merge.log
  ```
  工具自动处理:前条 start、后条 end、文本按序拼接、序号重排、source_merge.log 生成。
- 合并后立即 `tools/srt_tool.py validate VIDDIR/work/subtitle.srt`;拼接处标点衔接可用 Edit 微调。
- 合并量应克制;若合并范围超过 30% 条目,停止并走问题协议——可能源转写断句过碎,需告知用户(可建议换 whisper 模型重转写)。
