# 质量门槛 — 每阶段验收标准

> 铁律:产物未过本文件门槛,不得进入下一阶段。校验失败 → 回退修正或走问题协议,不得带着缺陷继续。
> 产物位置:交付物在 **VIDDIR 根**(源视频/烧录视频/封面/info.txt/报告),中间产物、状态、日志、记忆在 **VIDDIR/work/**;任何产物不得出现在项目文件夹或工作区根(视频目录以外)。

## 工具校验(每次 SRT 生成/修改后必须执行)

```bash
tools/srt_tool.py validate <file.srt>
```

- **exit 0**:通过,继续。
- **exit 1**(错误:序号错乱、时间轴非法):必须修正后重验。
- **exit 2**(警告:时间轴重叠/大间隙/空文本):**空文本条目必须清零**(翻译阶段自检的一部分);重叠/间隙若为 whisper 源自带且无法在合理成本内修正,在 issues.log 记录并告知用户,经同意后放行。

## 阶段门槛

| 阶段 | 门槛(全部满足才算通过) |
|------|--------------------------|
| 00 Preflight | check_env.sh exit 0 或 2(无 FAIL);work/session_state.json 已初始化,参数已与用户确认 |
| 01 Fetch | 根:`info.txt` 存在且含原标题/作者/URL/时长/扩展名;`video.*` 存在;work/run.log 记录 ok |
| 02 Transcribe | work/`subtitle.srt` validate 无错误;work/`audio.wav` 存在 |
| 03 Translate | work/`translated_subtitle.srt` validate **无错误且无警告(空文本清零)**;行数与源字幕条数一致(由 from-txt 强制);标题译文存在;记忆文件已按 memory.md 维护;work/`source_merge.log` 与 work/`selfcheck.log` 存在且内容可读;自检清单(见下)全部通过 |
| 04 Burn | 根:`video.burned.mp4` 存在且 ffprobe 可读;或 work/run.log 记录 skipped |
| 05 Report | `tools/report.py` 已生成根:`translation_report.md`;产物清单齐全;issues.log 中未解决条目已向用户说明 |

## 翻译自检清单(03 阶段 agent 必须逐项执行)

1. **源整理复核**:源整理(合并碎片)后,逐条确认没有合并错句子(语义被破坏),validate 无错误。
2. **逐块复查**:每个翻译块完成后,回读译文与原文比对:无漏句、无错位、无未翻译残留(英文原样出现在中文行)。
3. **术语一致性**:同一专名(人名/地名/组织/机制)在不同块中译文必须一致;不一致时统一并按 memory.md 更新术语表。
4. **广告检查**:广告段已翻译;广告内容未渗入术语表/元规则/前情提要;ad_memory.txt 已按 memory.md 追加。
5. **行数守恒**:翻译块的行数必须与对应源块严格一致(块内不得合并/拆分句子,句级一一对应);from-txt 行数校验失败即本块翻译不守恒。
6. **空文本清零**:`validate` 不允许出现空文本条目 WARN。
7. **重复自检**:全文终检时确认无相邻重复字幕(语义重复条目)。
8. **全文终检**:全部块完成后,通读 `translated_subtitle.srt` 一遍,确认无漏译错位;发现块间不一致处回改。

> 说明:旧流程的"规范化"与"校对"独立阶段已并入本阶段(见 workflow.md 设计原则)——源整理发生在翻译前,去重/填空类检查由上述自检完成。

## 05 阶段(Report):报告由工具生成

- 运行:`tools/report.py --vid-dir VIDDIR --output VIDDIR/translation_report.md`。
- 报告样板(任务参数/视频信息/交付物与中间产物清单/记忆摘要/运行流水/已知问题/交付清单)全部由工具从状态文件生成。
- **AI 不得手写重复样板**;如需补充人工观察(如翻译质量抽查结论),只允许在报告末尾「agent 补充说明」小节追加。
- 生成后核对:报告内容与 VIDDIR 实际状态一致(工具以文件系统为准,无需人工修正)。

## 交付清单(05 阶段向用户交付)

| 位置 | 文件 |
|------|------|
| VIDDIR 根 | `video.<ext>`(源视频)、`video.burned.mp4`(若烧录)、`thumbnail.png`、`info.txt`、`translation_report.md` |
| VIDDIR/work | `translated_subtitle.srt`(最终字幕)、`translated_title.txt`、记忆文件 4 个(`term_consistency_table.txt` / `meta_translation_rules.txt` / `synopsis_memory.txt` / `ad_memory.txt`) |

交付时向用户说明:根层是交付物;work/ 是过程文件(重跑/续跑/审阅用)。提示审阅记忆文件与最终字幕,如有问题可要求局部重译。

## 成本与效率建议(非强制)

- 短视频(≤15 分钟)一次全量翻译;长视频分块(每块 20~40 句),块间通过记忆文件衔接。
- 块翻译使用 prompts/translate-module.md 的约定,但由你(agent)决定块大小与重试策略——这是本 kits 与旧版 JSON 流水线最大的区别:把判断力还给模型。
