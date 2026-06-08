# RelayClip Server

RelayClip Server 是 RelayClip 的自建服务端。它是一个轻量 Go 服务，内置网页客户端，用来保存、同步和管理文本、链接、邮箱、电话和图片。

## 最快启动

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

访问：

```text
http://服务器IP:17006
```

## 镜像

当前镜像：

```text
ghcr.io/lixibi/relayclip-server:latest
```

预留 Docker Hub 镜像：

```text
docker.io/lixibi/relayclip-server:latest
```

Docker Hub 镜像正式发布前，建议使用 GHCR 镜像。

维护者启用 Docker Hub 发布时，需要在 GitHub 仓库里配置：

- Repository variable：`DOCKERHUB_ENABLED=true`
- Repository secret：`DOCKERHUB_USERNAME`
- Repository secret：`DOCKERHUB_TOKEN`

## 这个命令做了什么

- `--name relayclip-server`：容器名，方便查看日志和更新。
- `--restart unless-stopped`：服务器重启后自动恢复。
- `-p 17006:8080`：把宿主机 `17006` 映射到容器内 `8080`。
- `-v relayclip-data:/data`：把数据放到 Docker volume，更新容器不会丢。
- `KEYSERVER_DATA_FILE=/data/keys.json`：记录元数据保存位置。

## 检查状态

查看容器：

```bash
docker ps
```

查看日志：

```bash
docker logs relayclip-server
```

健康检查：

```bash
curl http://127.0.0.1:17006/api/health
```

## 更新

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

只要继续挂载 `relayclip-data:/data`，数据就会保留。

## 备份

```bash
docker run --rm \
  -v relayclip-data:/data \
  -v "$PWD":/backup \
  alpine \
  tar czf /backup/relayclip-data.tar.gz -C /data .
```

## HTTPS 反向代理

公网长期使用建议配置 HTTPS。Caddy 示例：

```caddy
clip.example.com {
    reverse_proxy localhost:17006
}
```

客户端填写：

```text
https://clip.example.com
```

## 数据目录

服务端会写入：

- `/data/keys.json`：记录元数据。
- `/data/assets/`：图片原图。
- `/data/assets/thumbs/`：图片缩略图。

## 能力

- 文本上传与获取。
- 图片上传、缩略图生成、原图读取。
- 文本分类：文本、图片、链接、邮箱、电话。
- 回收站：删除、恢复、永久删除、清空回收站。
- 内置网页版客户端。
- 健康检查：`GET /api/health`。
- 基础 HTTP timeout，避免慢连接长期占用。

## API

### 健康检查

```http
GET /api/health
```

### 文本接口

```http
GET  /api/get
POST /api/post
GET  /api/list
```

### 记录接口

```http
GET  /api/items
POST /api/items
GET  /api/items/latest
```

`GET /api/items` 支持：

- `category=text|image|link|email|phone`
- `include_deleted=1`
- `trash=1`

图片上传：

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

默认监听 `:8080`。可以通过环境变量指定数据文件和图片目录：

```bash
KEYSERVER_DATA_FILE=/tmp/relayclip/keys.json \
KEYSERVER_ASSET_DIR=/tmp/relayclip/assets \
go run .
```
