# 字幕翻译工作流 — 流程总纲

把在线视频(默认为英文)转成中文翻译字幕。流程由文档定义、脚手架工具执行确定性步骤、agent 完成语义性步骤。

## 阶段总览

| # | 阶段 | 负责人 | 工具 | 核心产物 | 进入下一阶段条件 |
|---|------|--------|------|----------|------------------|
| 00 | Preflight 预检 | agent | `tools/check_env.sh` | `session_state.json` | 环境检查通过(exit 0 或 2 且无 FAIL) |
| 01 | Fetch 抓取 | 工具 | `tools/fetch.sh` | `info.txt` `video.*` `thumbnail.png` | 文件存在且 info.txt 完整 |
| 02 | Transcribe 转写 | 工具 | `ffmpeg` + `tools/transcribe.py` + `tools/srt_tool.py` | `audio.wav` `subtitle.srt` `raw_subtitle.txt` | `srt_tool.py validate` 无错误 |
| 03 | Normalize 规范化 | agent | `tools/srt_tool.py` | `subtitle.normalized.srt` | validate 无错误 |
| 04 | Translate 翻译 | agent | `tools/srt_tool.py` | `translated_subtitle.srt` 及记忆文件 | from-txt 行数匹配 + validate 无错误 + 自检通过 |
| 05 | Proofread 校对 | agent | `tools/srt_tool.py` | `translated_subtitle.proofread.srt` | validate 无错误 |
| 06 | Report 交付 | agent | — | `translation_report.md` | 产物清单交给用户 |

> 06 Report 为收尾阶段:汇总产物、写报告、请用户审阅。不在 stages/ 单独设文件,见 quality.md「交付清单」。

## 入参清单(开工时必须确认)

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `url` | ✅ | — | 源视频 URL |
| `workspace` | ✅ | — | 工作区目录(每视频一个独立目录,须可写、路径不含空格/特殊字符) |
| `language` | 否 | `en` | 源语言代码(whisper 参数) |
| `whisper_model` | 否 | `turbo` | 转写模型:tiny/base/small/medium/large/large-v3/turbo |
| `proxy` | 否 | 无 | HTTP 代理地址(如 `http://127.0.0.1:7890`);环境不通时向用户索取 |
| `domain_hint` | 否 | 空 | 视频主题提示词(注入翻译上下文) |
| `burn_enabled` | 否 | `false` | 是否执行烧录(默认关闭;开启需用户明确要求) |

**确认方式**:会话开始时把表格念给用户核对,缺省值直接采用并在对话中说明。URL 与工作区缺一不可,缺失必须向用户询问,不得编造。

## 工作区布局(状态即文件)

```
<workspace>/
├── session_state.json          # 阶段状态与参数(续跑依据,每次阶段完成必须更新)
├── issues.log                  # 问题记录(问题协议专用)
├── run.log                     # 阶段执行流水(时间/阶段/结果)
├── info.txt                    # 视频元信息(fetch 产物)
├── video.<ext>                 # 原视频
├── thumbnail.png               # 封面
├── audio.wav                   # 音频(ffmpeg 抽取)
├── subtitle.srt                # whisper 原始字幕
├── raw_subtitle.txt            # 原始逐句文本(to-txt 产物)
├── subtitle.normalized.srt     # 规范化字幕(agent 编辑产物)
├── raw_subtitle.normalized.txt # 规范化逐句文本(翻译输入)
├── translated_title.txt        # 标题译文
├── translated_lines.txt        # 中文译文逐行(agent 写的核心产物,from-txt 输入)
├── translated_subtitle.srt     # 中文字幕(from-txt 生成)
├── translated_subtitle.proofread.srt  # 校对后字幕
├── raw_translated_subtitle.txt # 中文逐句文本(交付用)
├── term_consistency_table.txt  # 术语一致性表(记忆)
├── meta_translation_rules.txt  # 元翻译规则(记忆)
├── synopsis_memory.txt         # 前情提要(记忆)
├── ad_memory.txt               # 广告概括(记忆)
└── translation_report.md       # 交付报告
```

## session_state.json 约定

```json
{
  "url": "https://...",
  "workspace": "/abs/path",
  "params": { "language": "en", "whisper_model": "turbo", "proxy": null, "domain_hint": "" },
  "stages_completed": ["preflight", "fetch", "transcribe", "normalize", "translate", "proofread"]
}
```

- 每完成一个阶段,追加该阶段名到 `stages_completed` 并更新 `run.log`(写入一行 `[UTC时间] stage=<名> status=ok`)。
- **续跑规则**:开工时先读此文件。已有 `stages_completed` 的阶段:检查对应产物文件存在且通过 quality.md 门槛(只需 validate/存在性检查,不必重做),通过即跳过;产物缺失或校验失败则**重做该阶段**,并在 issues.log 记录一条。
- 阶段执行失败时状态不写完成,`run.log` 写 `status=fail`。

## 问题协议(摘要,全文在 AGENTS.md)

- 任何阻碍:记录 `issues.log` → 对话中 3 行内告知用户 → 等待指示 → 指出 kits 文档/工具缺陷并建议修复。
- **禁止**:自行改工具脚本、自行装依赖、自行换参数做实验、默默跳过阶段。
- 允许的变通仅限各 stage 文档「失败处置表」所列。

## 全局行为约束

- 广告内容(口播推广、优惠码、导流链接、三连号召)必须照常翻译,但**不得**写入术语表/元规则/前情提要(见 memory.md 与 prompts/ad-policy.md)。
- 每个 SRT 产物(02 起)生成后必须立即 `tools/srt_tool.py validate` 验证结构。
- 大文件下载、装依赖、换模型等动作前先征求用户同意。
