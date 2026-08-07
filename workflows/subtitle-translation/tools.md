# 本工作流工具清单与用法(tools.md)

> 本文件**全面描述本工作流可能用到的全部工具及其使用方法**,是工具用法的唯一权威。
> 各 stage 文档中的命令示例以本文件为准。工具返回非零退出码时,先读工具输出,再查对应 stage 文档「失败处置表」。
> **没有工具覆盖的能力 → 走问题协议反馈建议,禁止自造脚本。**

## 通用约定

- 所有工具位于 `tools/`(相对于项目文件夹根,即 `TranslationKits/tools/`)。
- **venv 引导**:所有 Python 工具(`transcribe.py`/`srt_tool.py`/`report.py`)自带 `.venv` 重执行引导,直接执行即可,无需指定解释器;禁止 sys.path hack。
- 退出码语义:非零 = 失败;具体含义见各工具。
- 工具只通过命令行参数接收路径,产物写入由调用方指定的路径(工作流约定:交付物在 VIDDIR 根、其余在 `VIDDIR/work/`)。

---

<a id="setup-venv"></a>
## 1. setup_venv.sh — 创建 Python 虚拟环境

创建 `TranslationKits/.venv` 并安装依赖(openai-whisper、srt)。

```
tools/setup_venv.sh
```

- 幂等:已存在则更新依赖。
- 需用户同意后才能运行(属安装依赖的大动作)。
- GPU 加速的 torch 版本见 02 阶段说明;本工具安装的是默认(CUDA)版 torch,AMD ROCm 机器需另行处理(见 check_env.sh 输出与 00 阶段失败处置表)。

<a id="check-env"></a>
## 2. check_env.sh — 环境预检(00 阶段起步必跑)

```
tools/check_env.sh [--workspace DIR] [--url URL] [--proxy PROXY]
```

- `--workspace`:工作区根目录(磁盘空间与可写性检查)。
- `--url`:源视频 URL(连通性检查;通不过会给出"可能需要代理"指引)。
- `--proxy`:HTTP 代理地址(如 `http://127.0.0.1:7890`),同时注入 yt-dlp/curl 环境。

检查项(输出 `[OK]`/`[WARN]`/`[FAIL]`):
1. 必需二进制:yt-dlp、ffmpeg、ffprobe、python3(node 缺失仅 WARN)。
2. Python/whisper 环境:优先 `.venv`,回退系统 python3;`import whisper, srt` 失败 → FAIL。
3. GPU 计算设备:
   - lspci 硬件检测(AMD/NVIDIA 显卡)。
   - torch 侧逐设备可用性探测(小矩阵试跑),跳过名字疑似 CPU 的设备。
   - 状态分类:GPU 可用 → OK;**有硬件但 torch 不可用 → FAIL(必须停下询问用户)**;无硬件 → WARN(仍需向用户确认一次)。
4. 工作区:可写性、磁盘空间(<5GB 警告)。
5. URL 连通性:yt-dlp 模拟提取;失败时用 curl 区分"网络不通(提示要代理)"与"URL 不可提取(提示确认 URL)"。

退出码:`0`=全部通过;`1`=有 FAIL(禁止继续,照 00 阶段失败处置表);`2`=仅警告(可继续)。

<a id="fetch"></a>
## 3. fetch.sh — 抓取元数据、视频与封面(01 阶段)

```
tools/fetch.sh --url URL --workspace DIR [--proxy PROXY]
```

- `--workspace` 传**工作区根**;工具从元数据标题生成安全目录名(空白→`_`,去掉 `" ' ,`),创建 `<workspace>/<视频名称>/`(VIDDIR)。
- 产物(均在 VIDDIR):
  - `info.txt`:原标题/作者/URL/上传日期/时长/扩展名/视频目录。
  - `video.<ext>`:原视频(已存在则跳过;`.part` 断点文件不算成品,会续传)。
  - `thumbnail.png`:封面(独立模板下载;失败仅警告)。
- 网络/超时均有硬超时与断点续传;失败时输出常见原因指引(URL 无效/需登录/地区限制/需代理)。
- 退出码:`0`=成功;`1`=失败(元数据失败或视频下载失败)。

<a id="transcribe"></a>
## 4. transcribe.py — whisper 音频转写为句级 SRT(02 阶段)

```
tools/transcribe.py <audio> --output <out.srt> [--model <M>] [--language <L>] [--device <D>] [--force]
```

- `--model`:tiny/base/small/medium/large/large-v3/turbo(默认 turbo)。
- `--language`:语言代码(默认 en;留空=自动检测)。
- `--device`:auto(默认)/cpu/cuda/cuda:N;auto 时逐设备可用性探测,自动跳过不可用设备(驱动不兼容等),全不可用回退 CPU 并打印提示(按 02 失败处置表处置)。
- 输出已存在且不早于音频时自动跳过;`--force` 强制重跑。
- 退出码:`0`=成功;`1`=失败(缺模型/网络下载失败等,按 02 失败处置表)。

<a id="srt-tool"></a>
## 5. srt_tool.py — SRT 结构工具(校验/转换/合并/拆块/拼块)

```
tools/srt_tool.py <子命令>
```

<a id="validate"></a>
### 5.1 validate — 结构校验(每个 SRT 产物生成后必跑)

```
tools/srt_tool.py validate <file.srt>
```

- 检查:序号连续(1..N)、start≤end、时间轴重叠/大间隙(>0.5s 警告)、空文本(警告)。
- 退出码:`0`=通过;`1`=错误(序号/时间轴非法,必须修正);`2`=警告(空文本必须清零,重叠/间隙按 quality.md 处置)。

<a id="to-txt"></a>
### 5.2 to-txt — SRT → 纯文本(每行一条)

```
tools/srt_tool.py to-txt <file.srt> <out.txt>
```

<a id="from-txt"></a>
### 5.3 from-txt — 纯文本 + 源时间轴 → SRT

```
tools/srt_tool.py from-txt --source <file.srt> --text <in.txt> --output <out.srt>
```

- 行数与源条数不一致 → FAIL(exit 1)。通用转换工具;03 分块流程请用 compose。

<a id="merge"></a>
### 5.4 merge — 合并条目 + 序号重排 + 合并日志(03 源整理必用)

```
tools/srt_tool.py merge <file.srt> --from N-M [--from N2-M2 ...] \
  --output <out.srt> [--log <log>]
```

- `--from`:合并范围,可多次(`N` 或 `N-M`,按序给出、互不重叠,否则 FAIL)。
- 合并规则:取组内首条 start、末条 end,文本按序空格拼接;**序号自动重排**(禁止手算)。
- `--log`:写出合并日志,每行 `N-M => 合并后文本`(即 source_merge.log)。
- 退出码:`0`=成功;`1`=范围非法(越界/重叠/乱序)。
- 输出路径可与输入相同(原地更新)。

<a id="split"></a>
### 5.5 split — 拆分为块(03 分块翻译必用)

```
tools/srt_tool.py split <file.srt> --out-dir <dir> [--size N]
```

- `--size`:每块条数;`0` 或省略 = 单块(全量)。
- 产物:`block_0001.srt ...`(完整字幕块)+ `manifest.txt`(每行 `block_000N.srt 起-止`,即分块方案中间产物)。

<a id="compose"></a>
### 5.6 compose — 块译文拼接生成 SRT(03 拼块必用)

```
tools/srt_tool.py compose --source <file.srt> --blocks-dir <dir> \
  --output <out.srt> [--lines <out.txt>]
```

- 按 manifest.txt 顺序读取块译文 `translated_000N.txt`(对应 `block_000N.srt`)。
- 校验:缺块 → FAIL;任一块行数与源条目数不符 → FAIL(列出期望/实际)。
- 生成 SRT(时间轴取自 source)与译文纯文本(`--lines`)。
- 退出码:`0`=成功;`1`=缺块/行数错误/manifest 缺失。

<a id="stats"></a>
### 5.7 stats — 统计

```
tools/srt_tool.py stats <file.srt>
```

- 输出:条目数、总时长、文本长度均值/最短/最长。

<a id="burn"></a>
## 6. burn.sh — 字幕烧录(05 阶段,可选)

```
tools/burn.sh --video <video> --subtitle <subtitle.srt> --output <out.mp4> \
  [--gpu auto|cpu|vaapi] [--vaapi-device <dev>] \
  [--encoder libx264] [--enforce-source-bitrate] [--min-bitrate-kbps N]
```

- `--gpu`(默认 auto,GPU 行为与 transcribe 对齐):
  - `auto`:检测 h264_vaapi 编码器与 `/dev/dri/renderD*`;可用 → 硬件编码(打印设备);不可用 → 回退 CPU 并打印 WARN(需停下询问用户是否接受)。
  - `vaapi`:强制硬件编码,环境不支持 → FAIL(exit 1,询问用户降级)。
  - `cpu`:强制软件编码。
- `--vaapi-device`:指定 render 设备(默认自动选 renderD128/renderD129 首个存在的)。
- `--encoder libx264`:CPU 模式显式编码器。
- `--enforce-source-bitrate`:ffprobe 读取原视频码率,输出码率下限 = max(原视频码率, `--min-bitrate-kbps`)。
- 输出已存在 → 自动跳过。
- 退出码:`0`=成功;`1`=失败(参数/编码器/GPU 强制失败)。

<a id="report"></a>
## 7. report.py — 自动生成交付报告(06 阶段必用)

```
tools/report.py --vid-dir VIDDIR --output VIDDIR/translation_report.md
```

- 从工作区状态文件自动生成报告(样板内容,AI 不手写):任务参数、视频信息、交付物与中间产物清单、记忆文件摘要、运行流水(含**重复 stage 行标注**)、过程记录(preflight/source_merge/selfcheck/review 直接复用)、已知问题、**临时文件检查**(/tmp/opencode/<视频名>/ 残留)、交付清单。
- 退出码:`0`=成功;`1`=目录不存在等。

---

## 工具与阶段对照表

| 工具 | 阶段 | 必须调用时机 |
|------|------|--------------|
| check_env.sh | 00 | 开工第一步,任何 FAIL 未解决不得开始 |
| fetch.sh | 01 | 抓取元数据/视频/封面 |
| ffmpeg(文档内命令) + transcribe.py | 02 | 抽音频 + 转写 |
| srt_tool.py merge / split / compose | 03 | 源整理合并、拆块、拼块(禁止替代实现) |
| srt_tool.py validate | 02/03/04 | 每个 SRT 产物生成后 |
| srt_tool.py to-txt | 04 | 复核修正后同步 translated_lines.txt |
| burn.sh | 05 | burn_enabled=true 时 |
| report.py | 06 | 交付报告生成 |
