# TurboPush 部署传输通道

双向传输：Mac 侧 push，云机侧 pull。

## 目录

- `from-mac/` — Mac 准备好的东西，云机拉取
  - `patched-exes.zip` — 已打补丁的 `turbopush.exe` + `turbo_push_server.exe`
  - `deploy.ps1` — 云机侧部署脚本（自动定位/备份/替换/校验）
  - `INSTALL_PI.bat` — 安装 Node 22 + PI CLI
  - `AGENT_TASK.bat` — 备用部署脚本（bat 版）
- `to-mac/` — 云机把结果写这里，Mac 拉取
  - `deploy-result.log` — 部署日志

## 云机侧操作

```powershell
git clone https://github.com/jonyjanytb-dev/tp-transfer.git
cd tp-transfer
powershell -ExecutionPolicy Bypass -File from-mac\deploy.ps1
git add to-mac/deploy-result.log
git commit -m "deploy result"
git push
```

## 补丁内容（TurboPush 2.3.4，Windows x64）

| 目标 | 位置 | 改动 |
|---|---|---|
| GUI `user_is_vip` | `turbopush.exe` @ `0x140184cf0` | `4883ec38...` → `b801000000c3`（恒真） |
| 后端 `ExpiredCheck` | `turbo_push_server.exe` @ `0x14093d1a0` | `493b6610...` → `31c0c3`（恒否） |
| 前端 `isVip` | 内嵌资源 | 替换为会员态 blob |
