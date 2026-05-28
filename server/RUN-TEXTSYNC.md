# TextSync Docker Image

Published image:

```bash
ghcr.io/lixibi/textsync-server:latest
```

Standalone binary:

```bash
/home/keyserver/keyserver
```

Pull and run:

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

Open:

```text
http://YOUR_SERVER_IP:17006
```

Useful checks:

```bash
docker logs textsync-server
curl http://127.0.0.1:17006/api/get
```

Stop and remove:

```bash
docker rm -f textsync-server
```

Data is stored in the Docker volume `textsync-data`.
