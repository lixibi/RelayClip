# HEBE TEXT

一个极简、安全、高性能的密钥/文本中转服务。

支持中文、英文、数字，手机端友好，亮暗主题切换。

## 特性

- 纯静态前端（单 `index.html`）
- 支持 UTF-8 中文
- 默认亮色主题 + 记忆功能
- iOS Safari 复制粘贴优化
- Docker 部署，体积极小（< 15MB）
- 支持 HTTPS（通过反代或 Caddy/Nginx）

## 端口映射

- 外部端口：**17006**
- 容器内部端口：8080

## 快速部署（推荐）

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

访问地址：`http://你的IP:17006`

---

## 文件说明

- `keyserver` —— Go 编译后的静态二进制（Alpine 兼容）
- `index.html` —— 完整前端界面（已嵌入）
- `keys.json` —— 数据持久化文件
- `/data/keys.json` —— Docker 容器内默认持久化路径
- `docker-compose.yml` —— 推荐启动方式
- `Dockerfile` —— 极简多阶段构建

## 更新密钥方式

1. 浏览器访问 `http://IP:17006`
2. 在“更新密钥”输入框输入内容或粘贴
3. 点击“更新”按钮

最新内容会立即显示在第一张卡片，并可一键复制。

## HTTPS 建议

推荐使用 Caddy 或 Nginx Proxy Manager 反向代理 17006 端口，并开启自动 HTTPS。

示例 Caddy 配置：

```caddy
hebe.yourdomain.com {
    reverse_proxy localhost:17006
}
```

---

部署完成。

如需更新前端或逻辑，修改 `index.html` 或 `main.go` 后重新构建即可。

祝使用愉快！
