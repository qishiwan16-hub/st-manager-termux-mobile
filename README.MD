# ST Manager Termux Mobile

面向 Android + Termux 的移动端部署包。  
目标是：手机端执行一次脚本，自动从 GitHub 拉取代码并启动服务。

默认运行参数：
- 地址：`127.0.0.1`
- 端口：`3456`
- 数据目录：`/storage/emulated/0/SillyTavern/default-user`

## 快速开始

在手机 Termux 里直接执行：

```bash
pkg install -y curl
curl -fsSL https://raw.githubusercontent.com/qishiwan16-hub/st-manager-termux-mobile/main/install-termux.sh | bash
```

安装成功后访问：

```text
http://127.0.0.1:3456
```

## 一键脚本做了什么

`install-termux.sh` 分两阶段执行：

1. `bootstrap` 阶段
- 安装基础依赖：`nodejs-lts git curl jq tmux termux-api termux-services lsof cronie`
- 从 GitHub clone/pull 最新代码到 `~/apps/st-manager-termux-mobile`

2. `deploy` 阶段
- 执行 `termux-setup-storage`
- 自动选择可写数据目录（优先内部存储，再尝试外置存储）
- 写入 `app-config.json`
- 重新安装依赖：`npm install --omit=dev`
- 启动服务并执行健康检查
- 接入 runit 守护（可选）

## 自定义安装参数

```bash
REPO_URL=https://github.com/qishiwan16-hub/st-manager-termux-mobile.git \
BRANCH=main \
APP_DIR=~/apps/st-manager-termux-mobile \
DATA_PATH=/storage/emulated/0/SillyTavern/default-user \
ST_MANAGER_HOST=127.0.0.1 \
PORT=3456 \
bash install-termux.sh
```

参数说明：
- `REPO_URL`：仓库地址
- `BRANCH`：部署分支，默认 `main`
- `APP_DIR`：本地部署目录，默认 `~/apps/st-manager-termux-mobile`
- `DATA_PATH`：SillyTavern 数据根目录
- `ST_MANAGER_HOST`：监听地址，建议固定 `127.0.0.1`
- `PORT`：服务端口

## 日常运维

```bash
cd ~/apps/st-manager-termux-mobile

bash scripts/start.sh
bash scripts/stop.sh
bash scripts/status.sh
bash scripts/healthcheck.sh
bash scripts/log-rotate.sh
bash scripts/daily-health.sh
```

也可使用 npm 命令：

```bash
npm run termux:start
npm run termux:stop
npm run termux:status
npm run termux:health
npm run termux:log-rotate
npm run termux:daily-health
npm run termux:install-service
```

## 守护进程（termux-services / runit）

安装守护：

```bash
cd ~/apps/st-manager-termux-mobile
sv-enable
bash scripts/install-runit-service.sh
sv status st-manager
```

控制守护：

```bash
sv up st-manager
sv down st-manager
sv restart st-manager
sv status st-manager
```

可自定义服务名：

```bash
SERVICE_NAME=st-manager-mobile bash scripts/install-runit-service.sh
sv status st-manager-mobile
```

## 常见问题

### 1) `npm install` 报 `EACCES symlink`

原因：在共享存储路径安装 Node 依赖。  
建议：统一在 `~/apps/...` 运行，或直接使用一键脚本自动部署。

### 2) 路径测试提示“路径不存在”

先看挂载点：

```bash
ls -la /storage
```

然后创建并验证目录：

```bash
P=/storage/emulated/0/SillyTavern/default-user
mkdir -p "$P"/characters "$P"/worlds "$P"/chats
touch "$P/.rwtest" && rm "$P/.rwtest"
```

外置 SD 卡路径如果不可写，改用内部存储目录。

### 3) 网页打不开

按顺序排查：
1. `bash scripts/status.sh`
2. `bash scripts/healthcheck.sh`
3. 查看日志：`logs/app-YYYY-MM-DD.log`

说明：健康检查会优先检查 `/api/stats`，若该接口短暂返回 500，会自动回退检查 `/api/config`。
若安装阶段仍失败，脚本会自动输出 `app-config.json`、`status`、最近日志和 `/api/config` 响应，直接把整段输出贴出来即可继续定位。

### 4) 锁屏后进程被系统回收

建议：
1. 关闭 Termux 电池优化
2. 执行 `termux-wake-lock`
3. 启用 runit 守护 + 定时巡检

## 升级与回滚

升级：
1. 备份 `DATA_PATH` 数据目录
2. 重新运行一键脚本（会自动从 GitHub 拉最新代码）
3. 执行 `status` 和 `healthcheck` 验证

回滚：
1. `bash scripts/stop.sh`
2. 恢复旧版目录或旧分支
3. 重新执行安装脚本

## 安全建议

默认仅本机访问（`127.0.0.1`）。  
不要改成 `0.0.0.0` 对公网暴露。若要局域网访问，请先加鉴权。
