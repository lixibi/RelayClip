# HEBE TEXT Docker Image

Image tar:

```bash
/home/keyserver/hebetext-image.tar
```

Standalone binary:

```bash
/home/keyserver/keyserver
```

Load and run:

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

Open:

```text
http://YOUR_SERVER_IP:17006
```

Useful checks:

```bash
docker logs hebetext
curl http://127.0.0.1:17006/api/get
```

Stop and remove:

```bash
docker rm -f hebetext
```

Data is stored in the Docker volume `hebetext-data`.
