# 阶段 00 — Preflight 预检

## 目标
- 确认全部入参(workflow.md 入参清单)。
- 验证环境与 URL 连通性。
- 初始化/恢复 `session_state.json`,决定续跑策略。

## 输入
会话开始时用户的指令(URL、工作区、可选参数)。

## 步骤

1. **确认入参**:把入参清单(workflow.md 表格)向用户核对。缺省值直接采用并说明:`language=en`、`whisper_model=turbo`、`burn_enabled=false`。URL 或工作区缺失 → 停下询问,不得编造。
2. **读续跑状态**:若工作区已有 `session_state.json`,按 workflow.md「续跑规则」决定跳过哪些阶段;同时检查 `issues.log` 中是否有未解决条目,有则先向用户说明。
3. **环境预检**:
   ```bash
   tools/check_env.sh --workspace <workspace> --url <url> [--proxy <proxy>]
   ```
   - exit 0 → 通过。
   - exit 2 → 有警告,向用户简述警告内容后继续。
   - exit 1 → 看输出里 FAIL 项,按下方失败处置表处置。
4. **初始化状态**:写 `session_state.json`(url/workspace/params/stages_completed:[])与 `run.log` 首行。

## 产物
- `session_state.json`(已初始化,参数与用户确认一致)
- `run.log`

## 质量门槛
见 quality.md 阶段 00。

## 失败处置表

| 现象 | 处置(照表执行,不自行变通) |
|------|------------------------------|
| FAIL:未找到 yt-dlp/ffmpeg/ffprobe/python3 | 记录 issues.log;告知用户需要安装的系统包,请用户安装后重跑预检 |
| FAIL:whisper/srt 模块缺失 | 记录 issues.log;询问用户是否同意运行 `tools/setup_venv.sh` 创建虚拟环境(该脚本会 pip install openai-whisper,属大动作,需用户同意);同意后运行并重跑预检 |
| WARN:未找到 node | 记录;告知用户部分站点可能下载失败,继续;若后续 fetch 失败再处置 |
| FAIL:工作区不可写 | 告知用户换一个可写路径,请用户提供 |
| FAIL:URL 无法连通(网络原因) | **停下来向用户要代理**:`请提供代理地址(如 http://127.0.0.1:7890),或确认网络已通`;拿到代理后填入 params.proxy 并重跑 check_env |
| FAIL:URL 可达但 yt-dlp 提取失败 | 告知用户:URL 可能需登录/私有/地区限制;请用户确认 URL 有效性或提供可访问的 URL |
| 无法判断 | 走问题协议(AGENTS.md),记录并告知用户 |

> 本阶段只做预检与确认。任何 FAIL 都必须解决后才进入 01。
