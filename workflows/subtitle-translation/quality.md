# 质量门槛 — 每阶段验收标准

> 铁律:产物未过本文件门槛,不得进入下一阶段。校验失败 → 回退修正或走问题协议,不得带着缺陷继续。

## 工具校验(每次 SRT 生成/修改后必须执行)

```bash
tools/srt_tool.py validate <file.srt>
```

- **exit 0**:通过,继续。
- **exit 1**(错误:序号错乱、时间轴非法):必须修正后重验。
- **exit 2**(警告:时间轴重叠/大间隙/空文本):空文本条目必须处理(见校对阶段);重叠/间隙若为 whisper 源自带且无法在合理成本内修正,在 issues.log 记录并告知用户,经同意后放行。

## 阶段门槛

| 阶段 | 门槛(全部满足才算通过) |
|------|--------------------------|
| 00 Preflight | check_env.sh exit 0 或 2(无 FAIL);session_state.json 已初始化,参数已与用户确认 |
| 01 Fetch | `info.txt` 存在且含原标题/作者/URL/时长/扩展名;`video.*` 存在;run.log 记录 ok |
| 02 Transcribe | `subtitle.srt` validate 无错误;`raw_subtitle.txt` 行数 == subtitle.srt 条数(用 `wc -l` 比对) |
| 03 Normalize | `subtitle.normalized.srt` validate 无错误;条数与原 SRT 差距可解释(仅允许合并,不允许拆分/新增) |
| 04 Translate | `translated_subtitle.srt` validate 无错误;**行数与源字幕条数一致(由 from-txt 强制)**;标题译文存在;记忆文件已按 memory.md 维护;自检通过(见下) |
| 05 Proofread | `translated_subtitle.proofread.srt` validate 无错误;无空文本条目;仅发生去重/填空两类改动 |
| 06 Report | 产物清单齐全;translation_report.md 已写;issues.log 中未解决条目已向用户说明 |

## 翻译自检清单(04 阶段 agent 必须逐项执行)

1. **逐块复查**:每个翻译块完成后,回读译文与原文比对:无漏句、无错位、无未翻译残留(英文原样出现在中文行)。
2. **术语一致性**:同一专名(人名/地名/组织/机制)在不同块中译文必须一致;不一致时统一并按 memory.md 更新术语表。
3. **广告检查**:广告段已翻译;广告内容未渗入术语表/元规则/前情提要;ad_memory.txt 已按 memory.md 追加。
4. **行数守恒**:翻译块的行数必须与对应源块严格一致(块内不得合并/拆分句子,句级一一对应)。
5. **全文终检**:全部块完成后,用 `srt_tool.py to-txt` 导出 `translated_subtitle.srt` 与 `subtitle.normalized.srt` 的文本,逐行对拍一遍,确认无漏译错位;发现块间不一致处回改。

## 校对自检清单(05 阶段)

- 只做两类修改:去重(相邻条目语义重复)与填空(空文本并入相邻条目)。
- 禁止:重译、改写语义、润色、补充信息。
- 校对后 validate 必须无警告(空文本清零)。

## 交付清单(06 阶段向用户交付)

1. `translated_subtitle.proofread.srt`(最终字幕,若 05 被跳过则交付 `translated_subtitle.srt`)
2. `raw_translated_subtitle.txt`(纯文本版,供复制)
3. `translated_title.txt` + `info.txt`
4. 记忆文件:`term_consistency_table.txt` / `meta_translation_rules.txt` / `synopsis_memory.txt` / `ad_memory.txt`
5. `translation_report.md`(参数、各阶段产物路径、记忆文件摘要、已知问题)
6. 提示用户:审阅记忆文件与最终字幕;如有问题可要求局部重译。

## 成本与效率建议(非强制)

- 短视频(≤15 分钟)一次全量翻译;长视频分块(每块 20~40 句),块间通过记忆文件衔接。
- 块翻译使用 prompts/translate-module.md 的约定,但由你(agent)决定块大小与重试策略——这是本 kits 与旧版 JSON 流水线最大的区别:把判断力还给模型。
