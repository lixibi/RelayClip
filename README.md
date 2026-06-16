# RelayClip

RelayClip 是一个自建的剪贴板、文本和图片共享效率工具。你在自己的服务器上运行一个轻量服务端，然后用 iOS、macOS 和网页客户端在多台设备之间保存、上传、获取和管理内容。

它适合这些日常场景：

- 从 iPhone 把链接、验证码、邮箱、电话、备忘或图片发到自己的服务器。
- 在 Mac、iPad、浏览器或另一台设备上快速复制最近内容。
- 用 iOS 快捷指令上传剪贴板文本，或获取服务器上的最新文本。
- 用 macOS 菜单栏客户端记录本机剪贴板历史，需要时一键发到远程。
- 临时保存图片，通过缩略图快速浏览，需要时打开原图。

## 当前状态

| 模块 | 状态 | 说明 |
| --- | --- | --- |
| Server | 已支持 | Go 单体服务，内置网页端，支持文本、图片、缩略图、回收站和健康检查。 |
| Web | 已支持 | 打开服务端地址即可使用，不需要单独部署前端。 |
| iOS | 已支持 | SwiftUI 原生客户端，支持历史记录、分类、图片、回收站、快捷指令和 GitHub 更新入口。 |
| macOS | 已支持 | 菜单栏效率工具，本地优先记录剪贴板，可手动或自动发送到远程。 |
| Windows | 准备中 | 后续会按效率工具思路补 Windows 客户端，见 [Windows Client Plan](docs/windows-plan.md)。 |

## 快速开始

如果你已经有一台 Linux 服务器，并且安装了 Docker，可以先用下面这一条命令跑起来：

```bash
docker volume create relayclip-data
docker run -d \
  --name relayclip-server \
  --restart unless-stopped \
  -p 17006:8080 \
  -v relayclip-data:/data \
  -e KEYSERVER_DATA_FILE=/data/keys.json \
  ghcr.io/lixibi/relayclip-server:latest
```

然后在浏览器打开：

```text
http://你的服务器IP:17006
```

如果页面能打开，就说明服务端已经跑起来了。接下来在 iOS 或 macOS 客户端的设置里填写同一个地址。

## Docker 镜像

当前可用镜像：

```text
ghcr.io/lixibi/relayclip-server:latest
```

项目已经预留 Docker Hub 发布配置。Docker Hub 镜像准备好后，会使用：

```text
docker.io/lixibi/relayclip-server:latest
```

在 Docker Hub 镜像正式发布前，建议先使用 GHCR 镜像。

维护者启用 Docker Hub 发布时，需要在 GitHub 仓库里配置：

- Repository variable：`DOCKERHUB_ENABLED=true`
- Repository secret：`DOCKERHUB_USERNAME`
- Repository secret：`DOCKERHUB_TOKEN`

## 新手部署指南

### 1. 准备服务器

你需要：

- 一台能访问公网或局域网的服务器。
- Docker。
- 一个开放端口，例如 `17006`。

如果服务器没有安装 Docker，可以先参考 Docker 官方安装方式完成安装。

### 2. 启动 RelayClip

```bash
docker volume create relayclip-data
docker run -d \
  --name relayclip-server \
  --restart unless-stopped \
  -p 17006:8080 \
  -v relayclip-data:/data \
  -e KEYSERVER_DATA_FILE=/data/keys.json \
  ghcr.io/lixibi/relayclip-server:latest
```

这个命令会做几件事：

- 创建一个叫 `relayclip-server` 的容器。
- 把服务器的 `17006` 端口映射到容器里的 `8080`。
- 把数据放进 Docker volume `relayclip-data`，以后更新容器也不会丢。
- 容器异常退出或服务器重启后自动恢复。

### 3. 检查是否成功

查看容器：

```bash
docker ps
```

查看日志：

```bash
docker logs relayclip-server
```

检查健康状态：

```bash
curl http://127.0.0.1:17006/api/health
```

浏览器访问：

```text
http://你的服务器IP:17006
```

### 4. 配置客户端

在 iOS 或 macOS 客户端里打开设置，填写：

```text
http://你的服务器IP:17006
```

如果你配置了域名和 HTTPS，就填写：

```text
https://clip.example.com
```

### 5. 更新服务端

更新镜像：

```bash
docker pull ghcr.io/lixibi/relayclip-server:latest
docker rm -f relayclip-server
docker run -d \
  --name relayclip-server \
  --restart unless-stopped \
  -p 17006:8080 \
  -v relayclip-data:/data \
  -e KEYSERVER_DATA_FILE=/data/keys.json \
  ghcr.io/lixibi/relayclip-server:latest
```

只要继续挂载 `relayclip-data:/data`，历史记录和图片就会保留。

### 6. 备份数据

RelayClip 的数据主要在 Docker volume 里：

- `/data/keys.json`：文本和记录元数据。
- `/data/assets/`：图片原图。
- `/data/assets/thumbs/`：缩略图。

可以用下面命令导出备份：

```bash
docker run --rm \
  -v relayclip-data:/data \
  -v "$PWD":/backup \
  alpine \
  tar czf /backup/relayclip-data.tar.gz -C /data .
```

## 配置 HTTPS

公网长期使用建议配置 HTTPS。下面是一个 Caddy 反向代理示例：

```caddy
clip.example.com {
    reverse_proxy localhost:17006
}
```

配置完成后，客户端填写：

```text
https://clip.example.com
```

局域网或个人测试环境可以先用 HTTP。

## 客户端说明

### iOS

iOS 客户端支持：

- 上传文本和图片。
- 获取远程最新文本。
- 历史记录、分类筛选、置顶、隐藏、回收站。
- 图片缩略图和原图查看。
- 链接、邮箱、电话识别。
- 快捷指令：
  - 上传剪贴板文本
  - 获取远程文本
  - 打开快捷面板
- 帮助页检查 GitHub Release，并打开最新 IPA 下载入口。

iOS 不允许普通 App 静默自我安装，所以“更新”会跳转到 GitHub 最新 Release 或 IPA 文件，由用户按当前安装方式完成安装。

### macOS

macOS 客户端是菜单栏效率工具：

- 默认只记录本机剪贴板，不自动发送远程。
- 支持手动发送剪贴板或单条历史记录到服务器。
- 支持自动发送开关。
- 支持菜单栏快捷复制、浮动窗口、分类筛选、图片缩略图和多行文本预览。
- 支持自定义快捷键打开浮动窗口。

macOS 源码在 [`macos/`](macos/) 目录中，按 SwiftPM macOS app 维护。

### Web

服务端内置网页客户端。打开服务端地址即可：

- 上传文本。
- 上传图片。
- 查看最新内容和历史记录。
- 复制文本。
- 预览图片。

## 功能亮点

- 自部署：服务端由你自己运行，客户端只保存你配置的服务器地址。
- 文本和图片：支持普通文本、multipart 图片上传、缩略图生成、原图读取。
- 智能分类：文本、图片、链接、邮箱、电话。
- 内容提取：记录里包含链接、邮箱、电话时，客户端可直接打开网页、发邮件或拨号。
- 历史管理：置顶、隐藏、本地编辑、回收站、恢复、永久删除、清空回收站。
- 本地优先：macOS 后台剪贴板监听默认只写本机历史，避免无意上传。
- 轻量存储：记录元数据保存在 JSON 文件中，图片文件保存在数据目录。

## 服务端 API

- `GET /api/health`：健康检查和计数。
- `GET /api/get`：获取最新文本。
- `POST /api/post`：上传文本。
- `GET /api/list`：列出记录。
- `GET /api/items`：列出记录，支持 `category`、`include_deleted`、`trash` 查询。
- `POST /api/items`：上传文本或 multipart 图片。
- `GET /api/items/latest`：获取最新记录 JSON。
- `GET /api/assets/{id}`：读取图片或缩略图。
- `GET /api/trash`：列出回收站记录。
- `DELETE /api/items/{id}`：删除到回收站。
- `POST /api/items/{id}/restore`：恢复。
- `DELETE /api/items/{id}/permanent`：永久删除。
- `DELETE /api/trash/permanent`：清空回收站。

## 本地开发

服务端：

```bash
cd server
go test ./...
go test -race ./...
go run .
```

iOS：

```bash
xcodebuild -project RelayClip.xcodeproj -scheme RelayClip -destination 'generic/platform=iOS Simulator' build
```

Docker：

```bash
docker build -t relayclip-server ./server
docker run --rm -p 17006:8080 relayclip-server
```

## 发布说明

- 项目名称：RelayClip
- 当前 GHCR 镜像：`ghcr.io/lixibi/relayclip-server:latest`
- 预留 Docker Hub 镜像：`docker.io/lixibi/relayclip-server:latest`
- 默认端口：容器内 `8080`，推荐映射到宿主机 `17006`
- 推荐部署方式：Docker + 持久化 volume + HTTPS 反向代理
- Windows 客户端规划：[`docs/windows-plan.md`](docs/windows-plan.md)

## License

MIT License. See [LICENSE](LICENSE) for details.
