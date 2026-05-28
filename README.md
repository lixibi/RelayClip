# TextSync iOS

TextSync iOS is a native SwiftUI client for syncing text through a lightweight relay server. It targets iOS 16, stores the server address locally on device, and can work with any reachable TextSync server.

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
