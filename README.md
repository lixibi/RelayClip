# RelayClip

RelayClip 是一个自建的剪贴板、文本和图片共享平台。你在自己的服务器上运行一个轻量 Go 服务端，然后用 iOS、macOS 或网页客户端在多台设备之间保存、上传、获取和管理内容。

它以前叫 TextSync。现在项目已经不只是“文本同步”：它支持图片上传、缩略图、原图查看、链接/邮箱/电话提取、回收站、快捷指令和 macOS 菜单栏工作流，所以更适合作为一个自部署的个人剪贴板平台来发布。

## 适合什么场景

- 从 iPhone 把文本、链接、邮箱、电话或图片发到自己的服务器。
- 在另一台设备上一键获取最新文本，或从历史记录里复制。
- 用 iOS 快捷指令上传剪贴板文本、获取远程最新文本。
- 用 macOS 菜单栏客户端记录本地剪贴板，并按需一键发送到远程。
- 临时保存图片，通过缩略图快速浏览，需要时打开原图。
- 用浏览器直接访问服务端，完成文本和图片的基础上传、复制和预览。

## 客户端

| 客户端 | 状态 | 说明 |
| --- | --- | --- |
| iOS | 已支持 | SwiftUI 原生客户端，支持历史记录、分类筛选、图片、回收站、半屏快捷面板、快捷指令和 GitHub 更新入口。 |
| macOS | 已支持 | 菜单栏工具。默认只记录本机剪贴板历史，不自动发送到远程；可通过开关启用自动发送，也可一键发送到远程。macOS 源码按本机独立目录维护，不放进当前 iOS 仓库。 |
| Web | 已支持 | 服务端自带网页客户端，浏览器访问服务器地址即可使用，支持文本和图片上传、复制、预览。 |
| Shortcuts | 已支持 | iOS 快捷指令可上传剪贴板文本、获取最新远程文本；获取时会跳过图片，返回最新文本记录。 |

## 功能亮点

- 自部署：服务端由你自己运行，客户端只保存你配置的服务器地址。
- 文本和图片：支持普通文本、multipart 图片上传、缩略图生成、原图读取。
- 智能分类：文本、图片、链接、邮箱、电话。
- 内容提取：记录里包含链接、邮箱、电话时，客户端可直接打开网页、发邮件或拨号。
- 图片体验：本地图片缓存、缩略图快速加载、原图查看。
- 历史管理：置顶、隐藏、本地编辑、回收站、恢复、永久删除、清空回收站。
- macOS 本地优先：后台剪贴板监听默认只写本机历史；只有手动点击或打开自动开关才发送到远程。
- iOS 快捷指令：
  - 上传剪贴板文本
  - 获取远程文本，自动跳过图片记录，只取最新文本
- 更新入口：帮助页可打开 GitHub 项目、检查最新 Release，并跳转到最新版下载入口。
- 服务端健康检查：`GET /api/health`
- 轻量存储：记录元数据保存在 JSON 文件中，图片文件保存在数据目录。

## 部署服务端

服务端镜像由 GitHub Actions 发布到 GHCR。当前镜像名沿用旧项目名，方便兼容已有部署：

```bash
ghcr.io/lixibi/textsync-server:latest
```

推荐部署命令：

```bash
docker pull ghcr.io/lixibi/textsync-server:latest
docker volume create relayclip-data
docker run -d \
  --name relayclip-server \
  --restart unless-stopped \
  -p 17006:8080 \
  -v relayclip-data:/data \
  -e KEYSERVER_DATA_FILE=/data/keys.json \
  ghcr.io/lixibi/textsync-server:latest
```

部署完成后，浏览器访问：

```text
http://你的服务器IP:17006
```

如果要公网长期使用，建议用 Caddy 或 Nginx 反向代理到 `17006`，并配置 HTTPS：

```caddy
clip.example.com {
    reverse_proxy localhost:17006
}
```

然后客户端填写：

```text
https://clip.example.com
```

局域网或测试环境也可以填写：

```text
http://服务器IP:17006
```

## 客户端如何配合

1. 先部署服务端。
2. 打开 iOS 或 macOS 客户端，进入设置。
3. 填写服务器地址，例如 `https://clip.example.com`。
4. 点“测试连接”，确认能读取远端记录。
5. 使用“上传”“获取远程”“历史记录”“回收站”等功能。

macOS 客户端的推荐用法：

- 平时默认关闭自动发送，只把剪贴板变化记录在本机历史。
- 需要跨设备共享时，点击“一键发送到远程”。
- 如果希望它像自动同步工具一样工作，再打开“后台自动发送到远程”。

快捷指令可以直接调用 RelayClip：

- “上传剪贴板文本”：把传入文本或当前剪贴板文本上传到服务器。
- “获取远程文本”：获取最新的文本记录并复制到剪贴板。如果最新记录是图片，会继续寻找最新的文本记录。

## 服务端 API

- `GET /api/health`：健康检查和计数。
- `GET /api/get`：获取最新文本，兼容旧客户端。
- `POST /api/post`：上传文本，兼容旧客户端。
- `GET /api/list`：列出记录，兼容旧客户端。
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
xcodebuild -project TextSync.xcodeproj -scheme TextSync -destination 'generic/platform=iOS Simulator' build
```

macOS 客户端：

```bash
cd /Users/lee/Documents/TextSync-macOS
swift build
```

## 数据存储

服务端保持轻量，默认使用 JSON 文件存储记录，图片文件放在数据目录下的 `assets/`。Docker 部署时建议挂载 `/data`，这样容器更新不会丢失数据。

推荐数据目录：

- `/data/keys.json`：记录元数据。
- `/data/assets/`：图片原图。
- `/data/assets/thumbs/`：图片缩略图。

## 发布说明

- 项目公开名称：RelayClip
- 旧名称：TextSync
- Docker 镜像：`ghcr.io/lixibi/textsync-server:latest`
- 默认端口：容器内 `8080`，推荐映射到宿主机 `17006`
- 推荐部署方式：Docker + 持久化 volume + HTTPS 反向代理

## License

MIT License. See [LICENSE](LICENSE) for details.
