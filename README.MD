# ST Manager Termux Mobile（安卓移动端专用）

本项目是为 Android + Termux 准备的运行包，目标是“开箱即用、先跑起来”。

默认运行策略：
- 监听地址：`127.0.0.1`
- 端口：`3456`
- 默认数据目录：`/storage/emulated/0/SillyTavern/default-user`

## 1. 目录结构

- `.next/`：Next.js 运行产物
- `server.js`：服务入口
- `app-config.json`：数据路径配置
- `install-termux.sh`：一键安装脚本（推荐）
- `scripts/`：运维脚本（启动/停止/状态/健康检查/日志）
- `termux/runit/`：`termux-services` 的 runit 模板

## 2. 前置条件

手机需安装：
1. `Termux`（推荐 F-Droid 版本）
2. `Termux:API`（用于通知能力）
3. 可选：`Termux:Boot`（若你后续需要开机自启）

## 3. 一键安装（推荐）

### 3.1 手机端直接运行（无需手动拉代码）

```bash
pkg install -y curl
curl -fsSL https://raw.githubusercontent.com/qishiwan16-hub/st-manager-termux-mobile/main/install-termux.sh | bash
```

### 3.2 如果你已经有脚本文件

```bash
bash install-termux.sh
```

### 3.3 一键脚本会自动做什么

1. 安装基础依赖（`nodejs-lts`、`git`、`termux-services`、`curl`、`jq` 等）
2. 从 GitHub 拉取/更新代码到 `~/apps/st-manager-termux-mobile`
3. 执行 `termux-setup-storage`
4. 自动探测并创建可写数据目录（优先内部存储，再尝试外置存储）
5. 生成/更新 `app-config.json`
6. 重新安装依赖：`npm install --omit=dev`
7. 启动服务并做健康检查
8. 尝试接入 `runit` 守护

## 4. 自定义参数

可在安装时覆盖：

```bash
REPO_URL=https://github.com/qishiwan16-hub/st-manager-termux-mobile.git \
BRANCH=main \
APP_DIR=~/apps/st-manager-termux-mobile \
DATA_PATH=/storage/emulated/0/SillyTavern/default-user \
PORT=3456 \
HOSTNAME=127.0.0.1 \
bash install-termux.sh
```

参数说明：
- `REPO_URL`：GitHub 仓库地址
- `BRANCH`：要部署的分支（默认 `main`）
- `APP_DIR`：代码落地目录（默认 `~/apps/st-manager-termux-mobile`）
- `DATA_PATH`：SillyTavern 数据根目录
- `PORT`：服务端口
- `HOSTNAME`：监听地址（建议保持 `127.0.0.1`）

安装完成后访问：

```text
http://127.0.0.1:3456
```

## 5. 日常运维命令

```bash
cd ~/apps/st-manager-termux-mobile

# 启动 / 停止 / 状态
bash scripts/start.sh
bash scripts/stop.sh
bash scripts/status.sh

# 健康检查
bash scripts/healthcheck.sh

# 日志轮转与巡检
bash scripts/log-rotate.sh
bash scripts/daily-health.sh
```

或使用 npm 快捷命令：

```bash
npm run termux:start
npm run termux:stop
npm run termux:status
npm run termux:health
npm run termux:log-rotate
npm run termux:daily-health
npm run termux:install-service
```

## 6. 守护进程（termux-services / runit）

### 6.1 安装守护

```bash
cd ~/apps/st-manager-termux-mobile
sv-enable
bash scripts/install-runit-service.sh
sv status st-manager
```

### 6.2 控制守护

```bash
sv up st-manager
sv down st-manager
sv restart st-manager
sv status st-manager
```

### 6.3 自定义服务名（可选）

```bash
SERVICE_NAME=st-manager-mobile bash scripts/install-runit-service.sh
sv status st-manager-mobile
```

## 7. 移动端稳定性建议

1. 在 Android 系统中关闭 Termux 电池优化
2. 长时间运行建议加锁：
```bash
termux-wake-lock
```
3. 建议定时巡检（每 15 分钟）：
```bash
crontab -e
```
加入：
```cron
*/15 * * * * cd ~/apps/st-manager-termux-mobile && bash scripts/daily-health.sh >/dev/null 2>&1
```
启动定时服务：
```bash
sv up crond
```

## 8. 常见问题排障

### Q1：`npm install` 报 `EACCES symlink`

原因：在共享存储（`/storage/...`）里安装 Node 依赖。  
处理：放到 `~/apps/...` 运行，或直接运行一键脚本（脚本会从 GitHub 部署到 `~/apps/st-manager-termux-mobile`）。

### Q2：配置测试提示“路径不存在”

先检查挂载点：

```bash
ls -la /storage
```

再验证并创建目录：

```bash
P=/storage/emulated/0/SillyTavern/default-user
mkdir -p "$P"/characters "$P"/worlds "$P"/chats
touch "$P/.rwtest" && rm "$P/.rwtest"
```

如果外置卡路径不可写，建议改回内部存储路径。

### Q3：网页打不开

按顺序检查：
1. `bash scripts/status.sh`
2. `bash scripts/healthcheck.sh`
3. 查看 `logs/app-YYYY-MM-DD.log`

### Q4：锁屏后进程被杀

1. 关闭电池优化
2. 开启 `termux-wake-lock`
3. 使用 runit + `daily-health.sh`

## 9. 升级与回滚

升级：
1. 备份数据目录（`DATA_PATH`）
2. 替换项目后重新执行 `bash install-termux.sh`
3. 用 `status` + `healthcheck` 验证

回滚：
1. `bash scripts/stop.sh`
2. 恢复上一版目录
3. 重新执行安装脚本

## 10. 安全说明

默认仅监听 `127.0.0.1`，请勿改成 `0.0.0.0` 对外暴露。  
如需局域网访问，建议先加鉴权（令牌或反向代理认证）。
