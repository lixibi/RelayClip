当前状态：已纳入 GitHub Actions Docker 构建发布流程。

产物：

- `ghcr.io/lixibi/textsync-server:latest`：GitHub Actions 发布的 Docker image
- `/home/keyserver/RUN-TEXTSYNC.md`：运行说明

验证结果：

- `go test ./...` 通过
- Docker 镜像使用多阶段构建生成 linux/amd64 静态 Go 二进制
- 运行镜像为 distroless，入口为 `/app/keyserver`

推荐运行方式：

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
