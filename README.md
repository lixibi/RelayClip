# TextSync

TextSync 是一个自部署的轻量剪贴板/文本中转项目。你在自己的服务器上运行一个 Go + Docker 服务端，然后用 iOS、macOS 或网页客户端上传、获取和管理内容。

它适合这些场景：

- 从 iPhone 把文本、链接、邮箱、电话或图片发到自己的服务器。
- 在另一台设备上一键获取最新文本，或从历史记录里复制。
- 用 iOS 快捷指令上传剪贴板文本、获取远程最新文本。
- 用 macOS 菜单栏客户端做桌面端快捷复制、上传和获取。
- 临时保存图片并通过缩略图预览，必要时打开原图。

## 客户端

- **iOS 客户端**：主客户端，SwiftUI 原生实现，支持历史记录、分类筛选、图片、回收站、快捷指令。
- **macOS 客户端**：菜单栏工具，适合桌面剪贴板工作流。macOS 客户端源码按本机独立目录维护，不放进当前 iOS 仓库。
- **网页客户端**：服务端自带 `index.html`，浏览器访问服务器地址即可使用，支持文本和图片上传/预览。

## 新特性

- 文本、图片、链接、邮箱、电话分类。
- 长按记录可提取链接、邮箱、电话号码；邮箱走 `mailto:`，电话走 `tel:`。
- 图片上传、缩略图预览、原图查看。
- 远端删除、回收站、恢复、永久删除、清空回收站。
- iOS 快捷指令：
  - 上传剪贴板文本
  - 获取远程文本，自动跳过图片记录，只取最新文本
- 服务端健康检查：`GET /api/health`
- 图片资产缓存优化，缩略图和原图带长期缓存头。

## 部署服务端

服务端镜像由 GitHub Actions 发布到 GHCR：

```bash
ghcr.io/lixibi/textsync-server:latest
```

推荐部署命令：

```bash
docker pull ghcr.io/lixibi/textsync-server:latest
docker volume create textsync-data
docker run -d \
  --name textsync-server \
  --restart unless-stopped \
  -p 17006:8080 \
  -v textsync-data:/data \
  -e KEYSERVER_DATA_FILE=/data/keys.json \
  ghcr.io/lixibi/textsync-server:latest
```

部署完成后，浏览器访问：

```text
http://你的服务器IP:17006
```

如果要公网长期使用，建议用 Caddy 或 Nginx 反向代理到 `17006`，并配置 HTTPS：

```caddy
textsync.example.com {
    reverse_proxy localhost:17006
}
```

然后客户端填写：

```text
https://textsync.example.com
```

局域网或测试环境也可以填写：

```text
http://服务器IP:17006
```

## 客户端如何配合

1. 先部署服务端。
2. 打开 iOS 客户端，进入设置。
3. 填写服务器地址，例如 `https://textsync.example.com`。
4. 点“测试连接”，确认能读取远端记录。
5. 使用“上传”“获取远程”“历史记录”“回收站”等功能。

快捷指令可以直接调用 TextSync：

- “上传剪贴板文本”：把传入文本或当前剪贴板文本上传到服务器。
- “获取远程文本”：获取最新的文本记录并复制到剪贴板。如果最新记录是图片，会继续寻找最新的文本记录。

## 服务端 API

- `GET /api/health`：健康检查和计数。
- `GET /api/list`：列出记录，兼容旧客户端。
- `GET /api/items`：列出记录，支持 `category`、`include_deleted`、`trash` 查询。
- `POST /api/post`：上传文本，兼容旧客户端。
- `POST /api/items`：上传文本或 multipart 图片。
- `GET /api/items/latest`：获取最新记录 JSON。
- `GET /api/assets/{id}`：读取图片或缩略图。
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

## 数据存储

服务端保持轻量，默认使用 JSON 文件存储记录，图片文件放在数据目录下的 `assets/`。Docker 部署时建议挂载 `/data`，这样容器更新不会丢失数据。

## License

MIT License. See [LICENSE](LICENSE) for details.
