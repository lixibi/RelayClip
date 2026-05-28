# TextSync iOS

TextSync iOS is a native SwiftUI client for syncing text through a lightweight relay server. It targets iOS 16, stores the server address locally on device, and can work with any reachable TextSync server.

<p>
  <img src="docs/images/textsync-home.jpg" alt="TextSync latest text screen" width="320">
  <img src="docs/images/textsync-history.jpg" alt="TextSync history screen" width="320">
</p>

## 中文说明

TextSync 是一个轻量级“文本中转”工具：在服务器上运行一个很小的 Docker 服务，然后用 iOS 客户端发送、获取和管理文本。适合公网服务器中转，也可以在局域网或测试环境里使用 HTTP 地址。

常用入口：

- iOS 安装包：查看 [最新 IPA Release](https://github.com/lixibi/iosTextSync/releases/tag/latest-ipa)
- Docker 镜像：`docker pull ghcr.io/lixibi/textsync-server:latest`
- 服务端说明：查看 [server/README.md](server/README.md)
- 自动构建：查看 [GitHub Actions](https://github.com/lixibi/iosTextSync/actions)

快速部署服务端：

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

部署完成后，在 iOS App 的设置里填写你的服务器地址即可。推荐使用 HTTPS 公网域名；测试时也允许使用 `http://IP:17006`。

## Features

- Fetch and display the latest shared text
- Browse recent history with local paging
- Pin important entries locally so they stay at the top
- Hide entries locally without deleting them from the server
- Copy the latest or historical text to the clipboard
- Paste from the clipboard and upload new text
- Edit the server address without rebuilding the app
- Run Shortcuts actions to upload the clipboard or fetch the latest remote text

## Server API

The bundled server source lives in `server/`. It is designed to run behind a public HTTPS reverse proxy for simple cross-device text relay.

- `GET /api/list` returns all entries as JSON
- `GET /api/get` returns the latest text
- `POST /api/post` uploads the request body as a new text entry

## Docker Server

GitHub Actions publishes the server image to GHCR:

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

Then point the iOS app at your public HTTPS domain or at `http://IP:17006` for local testing.

## GitHub Actions

Push this repository to GitHub, then run the workflow from the Actions tab. It builds an unsigned iOS IPA artifact and publishes the Docker server image.

## 致谢

- UI 设计参考了 [guokaigdg/animal-island-ui](https://github.com/guokaigdg/animal-island-ui) 的温暖、轻量和卡片式表达。
- iOS 客户端基于 SwiftUI、App Intents 和 Apple 平台能力开发。
- 服务端使用 Go 构建，并通过 Docker、GHCR 和 GitHub Actions 完成镜像发布与自动构建。
- 感谢所有相关开源项目和社区文档提供的基础能力与灵感。

## License

MIT License. See [LICENSE](LICENSE) for details.
