# 阶段 00 — Preflight 预检

## 目标
- 确认全部入参(workflow.md 入参清单)。
- 验证环境与 URL 连通性。
- 确定 VIDDIR(续跑或新任务),初始化/恢复状态。

## 输入
会话开始时用户的指令(URL、工作区、可选参数)。

## 步骤

1. **确认入参**:把入参清单(workflow.md 表格)向用户核对。缺省值直接采用并说明:`language=en`、`whisper_model=turbo`、`burn_enabled=false`。URL 或工作区缺失 → 停下询问,不得编造。
2. **确定 VIDDIR**:列出 `<workspace>` 的直接子目录:
   - 其 `work/session_state.json` 存在者 = 本视频目录;有多个则向用户确认选哪个。
   - 无 → 新任务:VIDDIR 尚未创建,由 01 fetch 阶段创建;此阶段不落盘。
3. **读续跑状态**:VIDDIR 已存在则读 `VIDDIR/work/session_state.json`,按 workflow.md「续跑规则」决定跳过哪些阶段;同时读 `VIDDIR/work/issues.log`,有未解决条目先向用户说明。
4. **环境预检**(注意:`--workspace` 传**工作区根**,不是 VIDDIR;视频目录此时可能还不存在,磁盘与可写性检查针对根目录即可)。**输出必须落盘**:视频目录已存在则 `tee` 到 `VIDDIR/work/preflight.log`;尚未创建则只用于对话与决策,并在 01 创建后补记一行摘要:
   ```bash
   tools/check_env.sh --workspace <workspace> --url <url> [--proxy <proxy>] | tee VIDDIR/work/preflight.log
   ```
   - exit 0 → 通过。
   - exit 2 → 有警告,向用户简述警告内容后继续。
   - exit 1 → 看输出里 FAIL 项,按下方失败处置表处置。
5. 新任务时:向用户确认无误后,声明"进入 01 fetch,VIDDIR 由 fetch 创建"。

## 产物
- 新任务:无(状态文件在 01 创建)。
- 续跑:确认 `session_state.json` 有效。

## 质量门槛
见 quality.md 阶段 00。

## 失败处置表

| 现象 | 处置(照表执行,不自行变通) |
|------|------------------------------|
| FAIL:未找到 yt-dlp/ffmpeg/ffprobe/python3 | 记录 issues.log(VIDDIR 未建则记工作区根);告知用户需要安装的系统包,请用户安装后重跑预检 |
| FAIL:whisper/srt 模块缺失 | 记录 issues.log;询问用户是否同意运行 `tools/setup_venv.sh` 创建虚拟环境(该脚本会 pip install openai-whisper,属大动作,需用户同意);同意后运行并重跑预检 |
| FAIL:torch 导入失败 | 记录 issues.log;告知用户 venv 可能损坏,询问是否同意运行 setup_venv.sh 重建 |
| WARN:未找到 node | 记录;告知用户部分站点可能下载失败,继续;若后续 fetch 失败再处置 |
| **GPU:有硬件但不可用**(check_env FAIL) | **停止**,按 AGENTS.md「GPU 询问协议」询问用户:是否有 GPU?是否尝试启用 GPU(可能需安装/更换驱动或 torch 版本)?还是 CPU 继续?决定后写入 `session_state.json` 的 `params.gpu`(auto/cpu)并重跑 check_env |
| **GPU:未检测到**(check_env WARN) | 向用户确认一次:是否确有 GPU 设备(独显未识别/外接 GPU)?确认后按 CPU 继续,`params.gpu=cpu` |
| FAIL:工作区不可写 | 告知用户换一个可写路径,请用户提供 |
| FAIL:URL 无法连通(网络原因) | **停下来向用户要代理**:`请提供代理地址(如 http://127.0.0.1:7890),或确认网络已通`;拿到代理后填入 params.proxy 并重跑 check_env |
| FAIL:URL 可达但 yt-dlp 提取失败 | 告知用户:URL 可能需登录/私有/地区限制;请用户确认 URL 有效性或提供可访问的 URL |
| 无法判断 | 走问题协议(AGENTS.md),记录并告知用户 |

> 本阶段只做预检与确认。任何 FAIL 都必须解决后才进入 01。GPU 状态未与用户确认前,不得进入转写/烧录阶段。
