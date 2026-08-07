# 阶段 03 — Translate 翻译(核心,含源整理)

## 目标

> **阶段导航**:上一阶段:[02 Transcribe](02-transcribe.md) | 下一阶段:[04 Review](04-review.md)
> 工作流总纲:[workflow.md](../workflow.md) | 工具清单:[tools.md](../tools.md) | 质量门槛:[quality.md](../quality.md)

把源字幕逐句翻译为中文,并维护四个记忆文件,产出 `translated_subtitle.srt`。**全部产物与记忆文件在 VIDDIR 内**。

本阶段包含三个子步骤:源整理(合并语法断裂碎片)、标题翻译、分块翻译,以及翻译完成后的自检(空文本清零、无重复,见 [quality.md](../quality.md) 自检清单)。

## 前置
- 02 通过;`VIDDIR/work/subtitle.srt` 存在。
- 已与用户确认 `domain_hint`(可为空)。

## 步骤

### A. 源整理
1. 通读 `VIDDIR/work/subtitle.srt` 全部条目,按 [prompts/normalize.md](../prompts/normalize.md) 判定合并:
   - 默认不合并;只有语法/句法被明显错误切断时才合并。
   - 得出合并清单:`N-M`(第 N 到 M 条合并为一条)。
2. **用工具执行合并**(禁止手算序号或写脚本;合并日志由工具生成):
   ```bash
   tools/srt_tool.py merge VIDDIR/work/subtitle.srt \
     --from N-M [--from N2-M2 ...] \
     --output VIDDIR/work/subtitle.srt --log VIDDIR/work/source_merge.log
   ```
   - 工具自动:取前条 start、后条 end、文本按序拼接、序号重排、生成 source_merge.log。
   - 无合并时:创建 `VIDDIR/work/source_merge.log` 写入一行"无合并"(或跳过本步骤并注明)。
3. 校验: `tools/srt_tool.py validate VIDDIR/work/subtitle.srt`。
4. 自检:合并量克制(>30% 条目停止并走问题协议);合并后抽查确认语义未破坏(被拼接的文本可再用 Edit 微调,如标点衔接)。

### B. 标题翻译
按 [prompts/title.md](../prompts/title.md) 翻译,写入 `VIDDIR/work/translated_title.txt`(已存在则跳过)。

### C. 分块翻译(块拆分与拼接由工具完成)
1. **拆块**(块大小自定:短视频一次全量即 `--size 0`;长视频 20~40 句/块):
   ```bash
   tools/srt_tool.py split VIDDIR/work/subtitle.srt --out-dir VIDDIR/work/blocks --size <N>
   ```
   生成 `work/blocks/block_0001.srt...` 与 `manifest.txt`(块→行范围映射,即分块方案中间产物)。
2. 读 `VIDDIR` 内四个记忆文件(不存在视为"尚无")。
3. 逐块翻译(按 [prompts/translate-module.md](../prompts/translate-module.md)):
   - 读 `VIDDIR/work/blocks/block_000N.srt` → 注入记忆文件与上文译文 → 请求模型输出 JSON → 校验行数 → 提取译文。
   - **块译文落盘**:译文逐行写入 `VIDDIR/work/blocks/translated_000N.txt`(每行一句,与块内条数一致)。
   - 按 memory.md 更新四个记忆文件。
   - 续跑即看 blocks 目录缺哪个 `translated_000N.txt`,补译该块即可。
4. **拼块生成最终字幕与译文**(行数/缺块校验由工具强制):
   ```bash
   tools/srt_tool.py compose --source VIDDIR/work/subtitle.srt \
     --blocks-dir VIDDIR/work/blocks \
     --output VIDDIR/work/translated_subtitle.srt \
     --lines VIDDIR/work/translated_lines.txt
   ```

### D. 校验与自检
1. `tools/srt_tool.py validate VIDDIR/work/translated_subtitle.srt`(必须 exit 0,空文本 WARN 清零)。
2. 执行 quality.md「翻译自检清单」全部 8 项(源整理复核、逐块复查、术语一致性、广告检查、行数守恒、空文本清零、重复自检、全文终检)。
3. **自检结果落盘**:把 8 项结果逐项写入 `VIDDIR/work/selfcheck.log`(每行 `[UTC时间] N. 项目名: 通过/失败(说明)`;发现问题并修复的,记录修复动作)。
4. 更新 `VIDDIR/work/session_state.json` + `VIDDIR/work/run.log`。

## 产物(全部在 VIDDIR/work/ 内)
- `translated_title.txt`、`translated_subtitle.srt`(04 复核修正后为最终交付字幕)
- `source_merge.log`(合并记录,由 merge 工具生成)、`selfcheck.log`(自检记录)
- `blocks/`(`block_000N.srt` 源块、`translated_000N.txt` 块译文、`manifest.txt` 分块方案;compose 后 `translated_lines.txt` 亦由工具生成)
- 四个记忆文件(如内容有更新)

## 质量门槛
见 [quality.md 阶段 03](../quality.md)(自检清单 8 项全部执行并全部通过)。merge/split/compose 用法见 [tools.md](../tools.md#merge) 对应章节。

## 失败处置表

| 现象 | 处置 |
|------|------|
| 模型输出 JSON 解析失败/行数不符 | 携带错误信息重试 1~2 次;仍失败 → 块大小减半重试;同一块失败 3 次 → 记录 issues.log,告知用户(可能记忆文件或提示词有缺陷),停止并等待指示 |
| compose 报行数不匹配/缺块 | 定位是哪个块导致(按 compose 输出),修正该块译文(translated_000N.txt)后重跑 compose |
| 漏译/错位(自检发现) | 单句修复:对缺句单独补译,改写对应块译文;修复后重跑 compose + validate |
| 术语漂移(自检发现) | 按记忆文件统一译文,回改涉及块;更新术语表 |
| 广告段内容渗入记忆文件 | 从记忆文件移除广告条目,回改涉及块的记忆更新;确认 ad-policy.md 遵守 |
| validate 出现空文本 WARN | 补译缺失行后重跑 compose(空文本清零是门槛) |
| 源整理合并过多(>30%) | 停止,走问题协议:转写可能断句严重,建议换 whisper 模型重转写(需用户同意) |
| 上下文过长/模型能力不足导致质量下降 | 缩小块大小;必要时向用户建议更长上下文的模型(需用户同意更换) |

## 续跑注意
- 工作区即状态:记忆文件 + `translated_lines.txt` + session_state.json 可随时恢复(均在 VIDDIR 内)。
- 中断后重开:校验已完成的块(记忆文件与译文块数是否自洽),从第一个未完成块继续。
