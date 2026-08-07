# 字幕翻译工作流 — 流程总纲

把在线视频(默认为英文)转成中文翻译字幕。流程由文档定义、脚手架工具执行确定性步骤、agent 完成语义性步骤。

## 三个目录概念(必须先分清)

| 名称 | 是什么 | 位置示例 | 可写内容 |
|------|--------|----------|----------|
| **项目文件夹** | 本 kits 仓库(TranslationKits):AGENTS.md、workflows/、tools/ | `/home/cc/Documents/code/TranslationKits` | **禁止写入任何产物**。agent 只读文档与工具 |
| **工作区根** | 用户指定的目录,可容纳多个视频 | `/home/cc/Videos/Translates` | 只允许直接子目录 = 各视频目录(见下) |
| **视频目录(VIDDIR)** | 每个视频的全部产物所在,名称 = 视频标题安全名 | `<workspace>/<视频名称>/` | 该视频全部中间产物、状态、日志、记忆、交付物 |

- **VIDDIR 记号**:本文档及 stages/ 中所有 `VIDDIR` 指 `<workspace>/<视频名称>/`。视频名称由 fetch 阶段从元数据标题生成(安全化规则:空白 → `_`,去掉 `"` `'` `,`),并记录在 `VIDDIR/info.txt` 的「视频目录」行。
- **铁律:所有中间产物、状态文件、日志、记忆文件、交付物一律写入 VIDDIR;项目文件夹与工作区根(除视频目录本身)均不得落盘。**

## 设计原则:为什么只有 6 个阶段

本 kits 是旧版代码流水线(下载→拆音频→转写→建句→规范化→翻译→校对→烧录)的倒置实现。倒置后,凡是"模型语义判断能直接完成"的环节不再单独设阶段:

- **不做独立"规范化"阶段**:旧流程需要 LLM 输出 `merge:true/false` JSON 来合并断句,是因为代码流水线把"合句"做成独立步骤。倒置后 agent 在翻译阶段直接合并语法断裂的碎片(见 03 源整理子步骤),无需先跑一遍合并判定。
- **不做独立"校对"阶段**:旧流程的校对是清理 LLM JSON 输出产生的空条目/重复。倒置后 agent 直接写译文文本,不会产生空行;重复由翻译自检与 `validate` 的 WARN 检查兜底。
- **不保留纯文本视图中间文件**(raw_*.txt):那是给"只能读纯文本的 LLM 接口"准备的;agent 直接读写 SRT 结构。

## 阶段总览

| # | 阶段 | 负责人 | 工具 | 核心产物(均在 VIDDIR 下) | 进入下一阶段条件 |
|---|------|--------|------|----------|------------------|
| 00 | Preflight 预检 | agent | `tools/check_env.sh` | 续跑时检查 VIDDIR 内 `session_state.json` | 环境检查通过(exit 0 或 2 且无 FAIL) |
| 01 | Fetch 抓取 | 工具 | `tools/fetch.sh` | `info.txt` `video.*` `thumbnail.png` + 创建 VIDDIR | 文件存在且 info.txt 完整 |
| 02 | Transcribe 转写 | 工具 | `ffmpeg` + `tools/transcribe.py` | `audio.wav` `subtitle.srt` | `srt_tool.py validate` 无错误 |
| 03 | Translate 翻译 | agent | `tools/srt_tool.py` | `translated_subtitle.srt` 及记忆文件 | from-txt 行数匹配 + validate 无错误 + 自检通过 |
| 04 | Burn 烧录 | 工具 | `tools/burn.sh` | `video.burned.mp4`(仅 burn_enabled=true) | 产物存在;跳过时在 run.log 注明 |
| 05 | Report 交付 | agent | — | `translation_report.md` | 产物清单交给用户 |

> 05 Report 为收尾阶段:汇总产物、写报告、请用户审阅。不在 stages/ 单独设文件,见 quality.md「交付清单」。

## 入参清单(开工时必须确认)

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `url` | ✅ | — | 源视频 URL |
| `workspace` | ✅ | — | **工作区根目录**(可容纳多个视频;本视频产物在 `<workspace>/<视频名称>/`;须可写、路径不含空格/特殊字符) |
| `language` | 否 | `en` | 源语言代码(whisper 参数) |
| `whisper_model` | 否 | `turbo` | 转写模型:tiny/base/small/medium/large/large-v3/turbo |
| `proxy` | 否 | 无 | HTTP 代理地址(如 `http://127.0.0.1:7890`);环境不通时向用户索取 |
| `domain_hint` | 否 | 空 | 视频主题提示词(注入翻译上下文) |
| `burn_enabled` | 否 | `false` | 是否执行烧录(04 阶段);开启需用户明确要求 |

**确认方式**:会话开始时把表格念给用户核对,缺省值直接采用并在对话中说明。URL 与工作区缺一不可,缺失必须向用户询问,不得编造。

## 视频目录布局(状态即文件)

```
<workspace>/                          ← 工作区根(只含视频目录)
└── <视频名称>/                        ← VIDDIR(fetch 阶段创建)
    ├── session_state.json            # 阶段状态与参数(续跑依据,每次阶段完成必须更新)
    ├── issues.log                    # 问题记录(问题协议专用)
    ├── run.log                       # 阶段执行流水(时间/阶段/结果)
    ├── info.txt                      # 视频元信息(fetch 产物,含「视频目录」行)
    ├── video.<ext>                   # 原视频
    ├── thumbnail.png                 # 封面
    ├── audio.wav                     # 音频(ffmpeg 抽取;空间紧张可删,重转写时重新抽取)
    ├── subtitle.srt                  # whisper 转写字幕(03 源整理时直接编辑本文件)
    ├── translated_title.txt          # 标题译文
    ├── translated_lines.txt          # 中文译文逐行(from-txt 输入;行数守恒防线,保留)
    ├── translated_subtitle.srt       # 中文字幕(from-txt 生成;最终交付字幕)
    ├── term_consistency_table.txt    # 术语一致性表(记忆)
    ├── meta_translation_rules.txt    # 元翻译规则(记忆)
    ├── synopsis_memory.txt           # 前情提要(记忆)
    ├── ad_memory.txt                 # 广告概括(记忆)
    ├── translation_report.md         # 交付报告
    └── video.burned.mp4              # 烧录产物(仅 burn_enabled=true)
```

## session_state.json 约定

```json
{
  "url": "https://...",
  "workspace": "/abs/path",
  "vid_dir": "/abs/path/<视频名称>",
  "params": { "language": "en", "whisper_model": "turbo", "proxy": null, "domain_hint": "", "burn_enabled": false },
  "stages_completed": ["preflight", "fetch", "transcribe", "translate", "burn", "report"]
}
```

- 文件位于 **VIDDIR 内**(fetch 阶段创建 VIDDIR 后初始化)。
- 每完成一个阶段,追加该阶段名到 `stages_completed` 并更新 `run.log`(写入一行 `[UTC时间] stage=<名> status=ok`);04 被跳过时写 `status=skipped`。
- **续跑规则**:开工时先确认 VIDDIR——列出工作区根的直接子目录,含 `session_state.json` 者即本视频目录;有多个则向用户确认。已有 `stages_completed` 的阶段:检查对应产物文件存在且通过 quality.md 门槛(只需 validate/存在性检查,不必重做),通过即跳过;产物缺失或校验失败则**重做该阶段**,并在 issues.log 记录一条。
- 阶段执行失败时状态不写完成,`run.log` 写 `status=fail`。

## 问题协议(摘要,全文在 AGENTS.md)

- 任何阻碍:记录 `VIDDIR/issues.log` → 对话中 3 行内告知用户 → 等待指示 → 指出 kits 文档/工具缺陷并建议修复。
- **唯一例外**:VIDDIR 尚未创建(fetch 元数据阶段之前)时,记录到工作区根 `issues.log`,视频目录创建后不再迁移。
- **禁止**:自行改工具脚本、自行装依赖、自行换参数做实验、默默跳过阶段。
- 允许的变通仅限各 stage 文档「失败处置表」所列。

## 全局行为约束

- 广告内容(口播推广、优惠码、导流链接、三连号召)必须照常翻译,但**不得**写入术语表/元规则/前情提要(见 memory.md 与 prompts/ad-policy.md)。
- 每个 SRT 产物生成后必须立即 `tools/srt_tool.py validate` 验证结构(02 的 subtitle.srt、03 的 translated_subtitle.srt)。
- 大文件下载、装依赖、换模型等动作前先征求用户同意。
- GPU 设备由 transcribe.py 自动探测选择(见 02 阶段);如转写明显过慢或报 HIP 错误,按 02 失败处置表处理。
