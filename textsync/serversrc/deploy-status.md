当前状态：已完成测试、Docker 化、容器验证和镜像 tar 导出。

产物：

- `/home/keyserver/hebetext-image.tar`：Docker image tar，镜像名 `hebetext:latest`
- `/home/keyserver/hebetext-image.tar.sha256`：校验和
- `/home/keyserver/keyserver`：从已验证镜像中导出的 linux/amd64 静态二进制
- `/home/keyserver/keyserver.sha256`：二进制校验和
- `/home/keyserver/RUN-HEBETEXT.md`：运行说明

验证结果：

- `go test ./...` 通过
- Docker 镜像使用 `golang:1.25` 构建 linux/amd64 静态 Go 二进制
- 运行镜像为 distroless，入口为 `/app/keyserver`
- 临时容器验证通过：
  - 首页可访问
  - `/api/post` 和 `/api/get` 正常
  - 129 个中文字符 + 129 个英文字符不会被截断
  - 超过 65536 字符返回 413
  - 容器重启后 Docker volume 中的数据可恢复

推荐运行方式：

```bash
docker load -i /home/keyserver/hebetext-image.tar
docker volume create hebetext-data
docker run -d \
  --name hebetext \
  --restart unless-stopped \
  -p 17006:8080 \
  -v hebetext-data:/data \
  -e KEYSERVER_DATA_FILE=/data/keys.json \
  hebetext:latest
```
