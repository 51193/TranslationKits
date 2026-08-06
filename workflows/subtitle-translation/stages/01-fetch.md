# 阶段 01 — Fetch 抓取

## 目标
下载视频元信息、原视频与封面到工作区。

## 前置
- 00 通过;`session_state.json` 中已有确认过的 url/workspace/proxy。

## 步骤

1. 下载(可能耗时长,开始前告知用户):
   ```bash
   tools/fetch.sh --url <url> --workspace <workspace> [--proxy <proxy>]
   ```
2. 读 `info.txt` 与 fetch 输出,在对话中向用户汇报:标题、作者、时长、扩展名。
3. 更新 `session_state.json`(stages_completed 追加 fetch)+ `run.log`。

## 产物
- `info.txt`(原标题/作者/URL/上传日期/时长/扩展名)
- `video.<ext>`(已存在则自动跳过)
- `thumbnail.png`(可选,缺失仅警告)

## 质量门槛
见 quality.md 阶段 01。

## 失败处置表

| 现象 | 处置(照表执行) |
|------|------------------|
| fetch.sh exit 1,错误为"元数据获取失败" | 读输出与 stderr:URL 无效/需登录 → 告知用户并请求确认 URL;地区限制/需要代理 → 请求代理(同 00 阶段)后重跑;两者都不是 → 走问题协议 |
| fetch.sh exit 1,错误为"视频下载失败" | 检查磁盘空间;网络中断/限速 → 告知用户后重试一次;需要代理 → 请求代理后重跑;仍失败 → 走问题协议 |
| 视频已存在但损坏(大小 < 1MB) | 记录 issues.log;删除后重跑 fetch.sh |
| fetch 超时(>10 分钟无输出) | 记录;告知用户网络缓慢,询问是否继续等待、使用代理或放弃 |

> 禁止:自行修改 yt-dlp 参数、自行换下载方式、自行拼接命令行。
