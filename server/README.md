# RelayClip Server

RelayClip Server 是一个轻量 Go 服务，用来给 iOS、macOS 和网页客户端做自建剪贴板、文本和图片共享。它保持单体、简洁、易部署：文本记录存 JSON，图片保存在本地 assets 目录，Docker 一条命令即可运行。

## 支持能力

- 文本上传与获取。
- 图片上传、缩略图生成、原图读取。
- 文本分类：文本、图片、链接、邮箱、电话。
- 回收站：删除、恢复、永久删除、清空回收站。
- 自带网页版客户端，浏览器打开服务端地址即可上传文本、上传图片、复制和预览。
- 健康检查：`GET /api/health`。
- 图片资产长期缓存。
- HTTP server 配置了基础 timeout，避免慢连接长期占用。

## 网页版客户端

RelayClip Server 内置 `index.html`，不需要额外部署前端。容器启动后，访问根路径即可打开网页版：

```text
http://服务器IP:17006
```

如果配置了 HTTPS 反向代理，也可以直接访问你的域名：

```text
https://clip.example.com
```

网页版支持文本上传、图片上传、最新内容查看、历史记录浏览、复制和图片预览，适合作为没有安装 iOS/macOS 客户端时的临时入口。

## Docker 镜像

GitHub Actions 会发布：

```bash
ghcr.io/lixibi/textsync-server:latest
```

## 推荐部署

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

访问：

```text
http://服务器IP:17006
```

客户端连接时填写同一个地址。公网使用建议配置 HTTPS 反代：

```caddy
clip.example.com {
    reverse_proxy localhost:17006
}
```

然后客户端填写：

```text
https://clip.example.com
```

## 数据目录

Docker 命令里挂载了：

```text
relayclip-data:/data
```

服务端会写入：

- `/data/keys.json`：记录元数据。
- `/data/assets/`：图片原图。
- `/data/assets/thumbs/`：图片缩略图。

更新镜像或重建容器时，只要保留这个 volume，数据就会保留。

## API

### 健康检查

```http
GET /api/health
```

返回 active、trash、total 和分类计数。

### 文本兼容接口

```http
GET  /api/get
POST /api/post
GET  /api/list
```

这些接口保留给旧客户端和简单脚本使用。

### 新记录接口

```http
GET  /api/items
POST /api/items
GET  /api/items/latest
```

`GET /api/items` 支持：

- `category=text|image|link|email|phone`
- `include_deleted=1`
- `trash=1`

图片上传使用 multipart：

```bash
curl -F "image=@photo.png" http://服务器IP:17006/api/items
```

### 图片资产

```http
GET /api/assets/{asset_id}
```

### 删除与回收站

```http
DELETE /api/items/{id}
POST   /api/items/{id}/restore
DELETE /api/items/{id}/permanent
GET    /api/trash
DELETE /api/trash/permanent
```

## 本地开发

```bash
go test ./...
go test -race ./...
go run .
```

默认监听 `:8080`。可以通过环境变量指定数据文件：

```bash
KEYSERVER_DATA_FILE=/tmp/textsync/keys.json go run .
```

也可以指定图片目录：

```bash
KEYSERVER_ASSET_DIR=/tmp/textsync/assets go run .
```
