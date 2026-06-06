# RelayClip Docker Image

Published image:

```bash
ghcr.io/lixibi/relayclip-server:latest
```

Standalone binary:

```bash
/home/keyserver/keyserver
```

Pull and run:

```bash
docker pull ghcr.io/lixibi/relayclip-server:latest
docker volume create relayclip-data
docker run -d \
  --name relayclip-server \
  --restart unless-stopped \
  -p 17006:8080 \
  -v relayclip-data:/data \
  -e KEYSERVER_DATA_FILE=/data/keys.json \
  ghcr.io/lixibi/relayclip-server:latest
```

Open:

```text
http://YOUR_SERVER_IP:17006
```

Useful checks:

```bash
docker logs relayclip-server
curl http://127.0.0.1:17006/api/get
```

Stop and remove:

```bash
docker rm -f relayclip-server
```

Data is stored in the Docker volume `relayclip-data`.
