# TextSync Server

一个极简的文本中转服务，可搭配 TextSync iOS 客户端实现跨设备文本同步。

支持 UTF-8 文本、手机端网页访问、亮暗主题切换和 Docker 部署。

## 特性

- 纯静态前端（单 `index.html`）
- 支持 UTF-8 中文
- 默认亮色主题 + 记忆功能
- Docker 部署，体积极小（< 15MB）
- 支持 HTTPS（通过反代或 Caddy/Nginx）

## 端口映射

- 外部端口：**17006**
- 容器内部端口：8080

## 快速部署（推荐）

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

访问地址：`http://你的IP:17006`

---

## 文件说明

- `keyserver` —— Go 编译后的服务端二进制
- `index.html` —— 完整前端界面（已嵌入）
- `keys.json` —— 数据持久化文件
- `/data/keys.json` —— Docker 容器内默认持久化路径
- `docker-compose.yml` —— 推荐启动方式
- `Dockerfile` —— 极简多阶段构建

## 更新文本方式

1. 浏览器访问 `http://IP:17006`
2. 在“更新文本”输入框输入内容或粘贴
3. 点击“更新”按钮

最新内容会立即显示在第一张卡片，并可一键复制。

## HTTPS 建议

推荐使用 Caddy 或 Nginx Proxy Manager 反向代理 17006 端口，并开启自动 HTTPS。

示例 Caddy 配置：

```caddy
textsync.yourdomain.com {
    reverse_proxy localhost:17006
}
```

---

部署完成。

如需更新前端或逻辑，修改 `index.html` 或 `main.go` 后重新构建即可。

祝使用愉快！
