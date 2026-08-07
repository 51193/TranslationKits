# TranslationKits — 字幕翻译工作流工具包

把"视频 → 中文字幕"翻译流程做成**文档定义 + 工具脚手架**的 kit:由通用编码 agent(opencode)读取流程文档、调用脚手架工具、用自身判断力完成翻译。不再用程序代码硬编码流程,不再用 JSON schema 约束模型。

## 环境要求

- `yt-dlp`、`ffmpeg`、`ffprobe`、`python3`(建议同时安装 `nodejs`)
- Python 虚拟环境(`tools/setup_venv.sh` 一键创建,含 openai-whisper + srt)
- 可选:GPU(CUDA/ROCm),whisper 自动检测
- 一个能上网的 agent(opencode);网络受限时按流程向用户索取代理

## 快速开始

```bash
# 1. 初始化 Python 环境
tools/setup_venv.sh

# 2. 环境预检(可选,工作流内也会做)
tools/check_env.sh --url <URL> --workspace <WS_DIR>

# 3. 启动工作流(opencode 打开本仓库后)
opencode "翻译 https://www.youtube.com/watch?v=xxx 到 <你的工作区>/Translates/xxx"
```

agent 会:确认入参 → 环境预检 → 抓取 → 转写 → 翻译(含源整理)→ 复核(全文校对+整体复核)→ 烧录(可选)→ 交付报告。全程产物在工作区,支持断点续跑。

> 流程为旧版代码流水线的"倒置"实现:不再设独立的规范化/校对阶段(由翻译阶段内的源整理与自检承担),中间产物精简为最小集合(见 workflows/subtitle-translation/workflow.md 设计原则)。

## 目录分层(必须遵守)

| 层 | 位置 | 内容 |
|----|------|------|
| 项目文件夹 | 本仓库(`TranslationKits/`) | 只读文档与工具,**禁止写入任何产物** |
| 工作区根 | 用户指定,如 `<你的工作区>/Translates` | 只容纳各视频目录(直接子目录) |
| 视频目录 VIDDIR | `<workspace>/<视频名称>/` | **根层只放交付物**(源视频/烧录视频/封面/info.txt/报告);中间产物、状态、日志、记忆全部在 `VIDDIR/work/`;目录名由 fetch 阶段从标题生成(空白→`_`,去掉 `" ' ,`) |

## 目录结构

```
├── AGENTS.md                     # agent 入口:角色、铁律、问题协议
├── workflows/subtitle-translation/
│   ├── workflow.md               # 流程总纲:阶段总览、入参清单、目录分层、产物命名
│   ├── stages/00~06/             # 各阶段操作手册(含失败处置表)
│   ├── memory.md                 # 记忆文件约定(术语表/元规则/前情提要/广告)
│   ├── quality.md                # 质量门槛、自检清单、交付清单
│   └── prompts/                  # 可复用提示词片段
├── tools/                        # 脚手架工具(唯一代码)
│   ├── check_env.sh              # 环境预检(二进制/venv/GPU/磁盘/URL 连通)
│   ├── fetch.sh                  # yt-dlp 抓取元数据+视频+封面
│   ├── transcribe.py             # whisper 音频 → 句级 SRT(GPU 自动探测)
│   ├── srt_tool.py               # SRT 校验 / 转文本 / 重建 / 统计
│   ├── burn.sh                   # ffmpeg 字幕烧录(GPU vaapi / CPU)
│   ├── report.py                 # 自动生成交付报告(样板内容)
│   └── setup_venv.sh             # 创建 .venv 并安装依赖
└── requirements.txt
```

## 设计原则

1. **工作流是文档**:改流程 = 改 markdown,不重编译。
2. **脚手架是工具**:确定性步骤(download/whisper/ffmpeg/srt 结构/报告生成)由脚本保证,agent 不重造轮子、不写重复样板。
3. **判断力属于模型**:源整理、翻译、记忆维护由 agent 完成,不设 JSON 硬约束,靠质量门槛自检兜底。
4. **问题必须上报**:任何阻碍走「问题协议」——记录 issues.log、告知用户、等待指示、反馈 kits 缺陷。
5. **产物隔离与分层**:交付物只放 VIDDIR 根(源视频/烧录/封面/info/报告),其余全部进 `VIDDIR/work/`;项目文件夹与工作区根(视频目录以外)禁止落盘。
6. **元指令闭合**:入参、阶段、文件命名、日志格式全部由文档定义;agent 不得自行发明文件名、目录名或流程步骤。

## 与旧项目的关系

旧项目 `VideoSubtitleTranslator`(.NET 10 控制台)是把流程硬编码在 C# 里、用 JSON 输出契约约束 LLM 的实现,已停止演进。本 kit 是其"倒置"版本:流程定义文档化,执行权交给通用 agent。产物布局与记忆机制保持兼容,便于对照迁移。
