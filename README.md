# TurboPush Agent Bridge

**架构**：Mac 侧是「大脑」，云机 PI CLI 是「手」。通过本仓库双向通信。

```
我(Mac)                      GitHub                      云机 PI CLI
  │                            │                             │
  ├─ 写 from-mac/tasks/*.task ►│                             │
  │                            │◄── worker 轮询 ─────────────┤
  │                            │                             ├─ pi -p 执行
  │                            │◄── 回传 to-mac/results ─────┤
  ├─ 读 to-mac/results ◄───────┤                             │
  │                                                          │
  └─ 分析 → 写下一个 task ──────────────────────────────────┘
```

## 快速开始（云机侧）

### 一键装环境

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/jonyjanytb-dev/tp-transfer/main/from-mac/install-bridge.ps1 | iex"
```

它会装：Node 22 → PI CLI → Git for Windows → 拉取本仓库。

### 配置凭据

**方式 A：API Key（命令行，无需交互）**

```cmd
setx PI_API_KEY "sk-xxxxxxxx"
setx PI_MODEL   "deepseek/deepseek-chat"
```

**方式 B：交互式登录**（跑一次即可，凭据持久化）

```cmd
pi
/login
```

### 配置回传 Token

需要一个 **fine-grained PAT**：

1. 打开 https://github.com/settings/tokens?type=beta
2. **Repository access** → Only select repositories → `tp-transfer`
3. **Permissions** → Repository permissions → **Contents: Read and write**
4. 生成后：

```cmd
setx GH_TOKEN "github_pat_xxxxxxxx"
```

> 注意：`setx` 后需要**开新终端**才生效。

### 启动 worker

```cmd
cd %USERPROFILE%\tp-transfer
powershell -ExecutionPolicy Bypass -File from-mac\worker.ps1
```

**单次测试**（推荐先跑这个）：

```cmd
powershell -ExecutionPolicy Bypass -File from-mac\worker.ps1 -Once
```

**自定义间隔**（默认 20 秒）：

```cmd
powershell -ExecutionPolicy Bypass -File from-mac\worker.ps1 -Interval 30
```

## 目录结构

```
from-mac/                     ← Mac 给云机的
  install-bridge.ps1          一键装环境
  worker.ps1                  轮询守护（核心）
  deploy.ps1                  TurboPush 补丁部署
  patched-exes.zip            已打补丁的 exe (25MB)
  tasks/                      任务队列
    001-deploy.task
to-mac/
  results/                    云机回传的结果
```

## 任务格式

`from-mac/tasks/<名字>.task` 是个 JSON：

```json
{
  "prompt": "给 PI 的自然语言指令",
  "tools": "read,bash,powershell,write",
  "timeout": 600
}
```

- `prompt` — 必填，PI 要执行的任务
- `tools` — 可选，工具白名单（默认含 powershell）
- `timeout` — 可选，秒（默认 600）

worker 执行完会写 `done/<名字>` 标记，不会重复跑同一个任务。

## 结果格式

`to-mac/results/<名字>.result.json`：

```json
{
  "task": "001-deploy.task",
  "host": "WIN-K5FXQ7PIHBS",
  "time": "2026-10-15 03:30:00",
  "elapsed_s": 42,
  "exit_code": 0,
  "stdout": "...",
  "stderr": ""
}
```

## 补丁内容（TurboPush 2.3.4, Windows x64）

| 目标 | 位置 | 改动 |
|---|---|---|
| GUI `user_is_vip` | `turbopush.exe` @ `0x140184cf0` | → `b801000000c3`（`mov eax,1; ret` 恒真） |
| 后端 `ExpiredCheck` | `turbo_push_server.exe` @ `0x14093d1a0` | → `31c0c3`（`xor eax,eax; ret` 恒否） |
| 前端 `isVip` | 内嵌资源 | 替换为会员态 blob |
