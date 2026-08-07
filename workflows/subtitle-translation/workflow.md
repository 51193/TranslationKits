# 字幕翻译工作流 — 流程总纲

把在线视频(默认为英文)转成中文翻译字幕。流程由文档定义、脚手架工具执行确定性步骤、agent 完成语义性步骤。

## 三个目录概念(必须先分清)

| 名称 | 是什么 | 位置示例 | 可写内容 |
|------|--------|----------|----------|
| **项目文件夹** | 本 kits 仓库(TranslationKits):AGENTS.md、workflows/、tools/ | `<项目克隆路径>/TranslationKits` | **禁止写入任何产物**。agent 只读文档与工具 |
| **工作区根** | 用户指定的目录,可容纳多个视频 | `<你的工作区>/Translates` | 只允许直接子目录 = 各视频目录(见下) |
| **视频目录(VIDDIR)** | 每个视频的全部产物所在,名称 = 视频标题安全名 | `<workspace>/<视频名称>/` | 该视频全部中间产物、状态、日志、记忆、交付物 |

- **VIDDIR 记号**:本文档及 stages/ 中所有 `VIDDIR` 指 `<workspace>/<视频名称>/`。视频名称由 fetch 阶段从元数据标题生成(安全化规则:空白 → `_`,去掉 `"` `'` `,`),并记录在 `VIDDIR/info.txt` 的「视频目录」行。
- **交付物/中间产物分层**:VIDDIR 根层**只放交付物**(源视频、烧录视频、封面、info.txt、translation_report.md);**所有中间产物、状态文件、日志、记忆文件一律在 `VIDDIR/work/` 子目录**(见下方布局树)。
- **铁律:所有产物一律写入 VIDDIR 内(交付物在根层、其余在 work/);项目文件夹与工作区根(除视频目录本身)均不得落盘。**

> **工具清单**:本工作流可能用到的全部工具及其完整用法见 `tools.md`(同一目录),是工具用法的唯一权威。各 stage 文档的命令示例以 tools.md 为准;工具未覆盖的能力 → 走问题协议反馈,禁止自造脚本。

## 设计原则:为什么只有 6 个阶段

本 kits 是旧版代码流水线(下载→拆音频→转写→建句→规范化→翻译→校对→烧录)的倒置实现。倒置后,凡是"模型语义判断能直接完成"的环节不再单独设阶段:

- **不做独立"规范化"阶段**:旧流程需要 LLM 输出 `merge:true/false` JSON 来合并断句,是因为代码流水线把"合句"做成独立步骤。倒置后 agent 在翻译阶段直接合并语法断裂的碎片(见 03 源整理子步骤),无需先跑一遍合并判定。
- **不做独立"校对"阶段**:旧流程的校对是清理 LLM JSON 输出产生的空条目/重复。倒置后 agent 直接写译文文本,不会产生空行;重复由翻译自检与 `validate` 的 WARN 检查兜底。
- **不保留纯文本视图中间文件**(raw_*.txt):那是给"只能读纯文本的 LLM 接口"准备的;agent 直接读写 SRT 结构。

## 阶段总览

| # | 阶段 | 负责人 | 工具 | 核心产物 | 进入下一阶段条件 |
|---|------|--------|------|----------|------------------|
| 00 | Preflight 预检 | agent | `tools/check_env.sh` | 续跑时检查 `VIDDIR/work/session_state.json` | 环境检查通过(exit 0 或 2 且无 FAIL) |
| 01 | Fetch 抓取 | 工具 | `tools/fetch.sh` | 根:`info.txt` `video.*` `thumbnail.png`;work/:`session_state.json` `run.log` `issues.log` | 文件存在且 info.txt 完整 |
| 02 | Transcribe 转写 | 工具 | `ffmpeg` + `tools/transcribe.py` | work/:`audio.wav` `subtitle.srt` | `srt_tool.py validate` 无错误 |
| 03 | Translate 翻译 | agent | `tools/srt_tool.py` | work/:`translated_subtitle.srt`、`blocks/` 及记忆文件 | compose 行数匹配 + validate 无错误 + 自检通过 |
| 04 | Review 复核 | agent | `tools/srt_tool.py` | work/:`review.log`(全文校对+整体复核) | 校对完成、validate 无错误、复核结论通过 |
| 05 | Burn 烧录 | 工具 | `tools/burn.sh` | 根:`video.burned.mp4`(仅 burn_enabled=true) | 产物存在;跳过时在 run.log 注明 |
| 06 | Report 交付 | 工具 | `tools/report.py` | 根:`translation_report.md` | 报告生成且产物清单交给用户 |

> 04 Review 为翻译质量最后关卡:翻译完成后从全片视角做全文校对与整体复核(见 stages/04-review.md);06 Report 为收尾阶段:运行 tools/report.py 自动生成交付报告(见 stages/06-report.md)。

## 入参清单(开工时必须确认)

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `url` | ✅ | — | 源视频 URL |
| `workspace` | ✅ | — | **工作区根目录**(可容纳多个视频;本视频产物在 `<workspace>/<视频名称>/`;须可写、路径不含空格/特殊字符) |
| `language` | 否 | `en` | 源语言代码(whisper 参数) |
| `whisper_model` | 否 | `turbo` | 转写模型:tiny/base/small/medium/large/large-v3/turbo |
| `proxy` | 否 | 无 | HTTP 代理地址(如 `http://127.0.0.1:7890`);环境不通时向用户索取 |
| `domain_hint` | 否 | 空 | 视频主题提示词(注入翻译上下文) |
| `gpu` | 否 | `auto` | GPU 策略:auto(转写/烧录自动用可用 GPU)或 cpu;**修改必须来自用户决定**(见 AGENTS.md「GPU 询问协议」) |
| `burn_enabled` | 否 | `false` | 是否执行烧录(04 阶段);开启需用户明确要求 |

**确认方式**:会话开始时把表格念给用户核对,缺省值直接采用并在对话中说明。URL 与工作区缺一不可,缺失必须向用户询问,不得编造。

## 视频目录布局(交付物/中间产物分层;状态即文件)

```
<workspace>/                          ← 工作区根(只含视频目录)
└── <视频名称>/                        ← VIDDIR(fetch 阶段创建)
    ├── video.<ext>                   # 交付物:源视频
    ├── video.burned.mp4              # 交付物:烧录视频(仅 burn_enabled=true)
    ├── thumbnail.png                 # 交付物:封面
    ├── info.txt                      # 交付物:视频元信息(含「视频目录」行)
    ├── translation_report.md         # 交付物:交付报告(05 阶段 tools/report.py 自动生成)
    └── work/                         # 中间产物与状态(所有非交付物)
        ├── session_state.json        # 阶段状态与参数(续跑依据,每次阶段完成必须更新)
        ├── issues.log                # 问题记录(问题协议专用)
        ├── run.log                   # 阶段执行流水(时间/阶段/结果)
        ├── preflight.log             # 00:check_env.sh 完整输出(环境预检结果)
        ├── audio.wav                 # 音频(ffmpeg 抽取;空间紧张可删,重转写时重新抽取)
        ├── subtitle.srt              # whisper 转写字幕(03 源整理时直接编辑本文件)
        ├── source_merge.log          # 03:源整理合并记录(每条一行:原句号范围 => 合并后文本)
        ├── translated_title.txt      # 标题译文
        ├── translated_lines.txt      # 中文译文逐行(由 compose 生成;行数守恒防线,保留)
        ├── translated_subtitle.srt   # 中文字幕(compose 生成;04 复核修正后为最终交付字幕)
        ├── blocks/                   # 03 分块产物:block_000N.srt(源块)、translated_000N.txt(块译文)、manifest.txt(分块方案)
        ├── selfcheck.log             # 03:翻译自检记录(自检清单 8 项逐项结果)
        ├── review.log                # 04:复核记录(全文校对修正 + 整体复核结论)
        ├── term_consistency_table.txt    # 术语一致性表(记忆)
        ├── meta_translation_rules.txt    # 元翻译规则(记忆)
        ├── synopsis_memory.txt           # 前情提要(记忆)
        └── ad_memory.txt                 # 广告概括(记忆)
```

> 交付物 = 用户最终需要的东西,直接放在 VIDDIR 根;中间产物/状态/日志/记忆 = 过程文件,统一在 `work/`。交付清单见 quality.md。

## 操作输出落盘原则(一切输出都是中间产物)

- **任何会产生后续复用价值的操作输出,都必须写入 `VIDDIR/work/` 下的中间产物文件**:环境预检结果(preflight.log)、合并记录(source_merge.log)、自检结果(selfcheck.log)、复核记录(review.log)、问题记录(issues.log)、记忆文件(4 个)、状态(session_state.json)、流水(run.log)。
- **后续阶段只能从文件复用内容,不得从对话中复述**;对话仅用于进度说明与向用户提问。
- **AI 不得把已落盘的内容重复写进另一个文件或对话**(如报告正文中复述记忆内容——由 report.py 直接读取)。
- 判断标准:该输出是否会被后续阶段/续跑/审阅再次引用?是 → 必须落盘。

## session_state.json 约定

```json
{
  "url": "https://...",
  "workspace": "/abs/path",
  "vid_dir": "/abs/path/<视频名称>",
  "params": { "language": "en", "whisper_model": "turbo", "proxy": null, "domain_hint": "", "gpu": "auto", "burn_enabled": false },
  "stages_completed": ["preflight", "fetch", "transcribe", "translate", "review", "burn", "report"]
}
```

- 文件位于 **`VIDDIR/work/session_state.json`**(fetch 阶段创建 work/ 后初始化)。
- 每完成一个阶段,追加该阶段名到 `stages_completed` 并更新 `run.log`(`VIDDIR/work/run.log`,写入一行 `[UTC时间] stage=<名> status=ok`);04 被跳过时写 `status=skipped`。
- **续跑规则**:开工时先确认 VIDDIR——列出工作区根的直接子目录,其 `work/session_state.json` 存在者即本视频目录;有多个则向用户确认。已有 `stages_completed` 的阶段:检查对应产物文件存在且通过 quality.md 门槛(只需 validate/存在性检查,不必重做),通过即跳过;产物缺失或校验失败则**重做该阶段**,并在 issues.log 记录一条。
- 阶段执行失败时状态不写完成,`run.log` 写 `status=fail`。

## 问题协议(摘要,全文在 AGENTS.md)

- 任何阻碍:记录 `VIDDIR/work/issues.log` → 对话中 3 行内告知用户 → 等待指示 → 指出 kits 文档/工具缺陷并建议修复。
- **唯一例外**:VIDDIR 尚未创建(fetch 元数据阶段之前)时,记录到工作区根 `issues.log`,视频目录创建后不再迁移。
- **禁止**:自行改工具脚本、自行装依赖、自行换参数做实验、默默跳过阶段。
- 允许的变通仅限各 stage 文档「失败处置表」所列。

## 全局行为约束

- 广告内容(口播推广、优惠码、导流链接、三连号召)必须照常翻译,但**不得**写入术语表/元规则/前情提要(见 memory.md 与 prompts/ad-policy.md)。
- 每个 SRT 产物生成后必须立即 `tools/srt_tool.py validate` 验证结构(02 的 `work/subtitle.srt`、03 的 `work/translated_subtitle.srt`)。
- **禁止自造环节脚本**:合并、拆块、拼块、格式转换、结构检查一律用 `tools/srt_tool.py` 既有子命令;任何"发现工具缺能力"的情况 → 走问题协议反馈建议,不得为流程环节编写一次性脚本(冒烟教训:自造 merge 脚本导致序号位移等连环错误)。文本级小修正(如 03 拼接处标点、04 复核修正译文)直接用 Edit 工具编辑文件,不写脚本。
- **禁止内联 python 替代工具**:行数守恒(compose/from-txt 自带校验)、结构/空文本检查(validate 覆盖)不得用内联 python 重写;残留英文等语义检查靠通读完成。
- **Python 执行约定**:需要运行 python 时一律用 `tools/` 脚本(自带 .venv 引导)或 `TranslationKits/.venv/bin/python3`,禁止 sys.path 硬编码 hack。
- **临时文件约定**:理想状态是**不产生任何临时文件**(所有操作输出直接落盘 VIDDIR/work/)。确需临时文件时,一律放 `/tmp/opencode/<视频名>/`;**阶段结束立即清理**;06 交付时必须向用户反馈本次临时文件使用情况(路径、用途、是否已清理),无临时文件则明说"未使用临时文件"。report.py 会在报告「临时文件」节自动检查该目录残留。
- **禁止重复内容**:见 AGENTS.md 铁律 4——run.log/issues.log 不重复追加;字幕/译文/记忆/报告不得重复或复制粘贴中间产物内容;发现重复立即清理,并在 06 复核时检查 run.log 无重复 stage 行(有则清理后重跑 06)。
- 报告与一切可自动化的样板内容(报告、产物清单)由 `tools/` 生成,**AI 不得手写重复样板**;人工观察可追加在报告末尾(见 06 阶段)。
- 大文件下载、装依赖、换模型等动作前先征求用户同意。
- GPU 设备由 transcribe.py 自动探测选择(见 02 阶段);如转写明显过慢或报 HIP 错误,按 02 失败处置表处理。
