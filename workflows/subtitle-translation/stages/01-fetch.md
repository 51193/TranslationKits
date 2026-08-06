# 阶段 01 — Fetch 抓取

## 目标
下载视频元信息、原视频与封面,并**创建视频目录 VIDDIR**(`<workspace>/<视频名称>/`)。

## 前置
- 00 通过;已确认 url/workspace/proxy。

## 步骤

1. 下载(可能耗时长,开始前告知用户;`--workspace` 传**工作区根**,工具内部会创建 VIDDIR):
   ```bash
   tools/fetch.sh --url <url> --workspace <workspace> [--proxy <proxy>]
   ```
2. 从输出与 `VIDDIR/info.txt` 确认:**VIDDIR 路径**(输出含「视频目录」行)、标题、作者、时长、扩展名,在对话中向用户汇报。
3. **初始化状态**:VIDDIR 已创建,立即写入:
   - `VIDDIR/session_state.json`(url/workspace/vid_dir/params/stages_completed:["fetch"])
   - `VIDDIR/run.log` 首行
4. 若工作区根存在旧 `issues.log`(00 阶段例外记录),把内容并入 `VIDDIR/issues.log` 后删除根级文件。
5. 更新 `session_state.json`(stages_completed 追加 fetch)+ `run.log`。

## 产物(全部在 VIDDIR 内)
- `info.txt`(原标题/作者/URL/上传日期/时长/扩展名/**视频目录**)
- `video.<ext>`(已存在则自动跳过)
- `thumbnail.png`(可选,缺失仅警告)
- `session_state.json`、`run.log`、`issues.log`

## 质量门槛
见 quality.md 阶段 01。

## 失败处置表

| 现象 | 处置(照表执行) |
|------|------------------|
| fetch.sh exit 1,错误为"元数据获取失败" | VIDDIR 尚未创建:例外地记工作区根 `issues.log`。读输出与 stderr:URL 无效/需登录 → 告知用户并请求确认 URL;地区限制/需要代理 → 请求代理(同 00 阶段)后重跑;两者都不是 → 走问题协议 |
| fetch.sh exit 1,错误为"视频下载失败" | 此时 VIDDIR 与 info.txt 已生成(可从 info.txt 读到 VIDDIR 路径)。检查磁盘空间;网络中断/限速 → 告知用户后重试一次;需要代理 → 请求代理后重跑;仍失败 → 走问题协议 |
| 视频已存在但损坏(大小 < 1MB) | 记录 issues.log;删除后重跑 fetch.sh |
| fetch 超时(>10 分钟无输出) | 记录;告知用户网络缓慢,询问是否继续等待、使用代理或放弃 |

> 禁止:自行修改 yt-dlp 参数、自行换下载方式、自行拼接命令行、自行在其他位置创建产物。
