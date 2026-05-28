FROM golang:1.25 AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/keyserver ./

FROM gcr.io/distroless/base-debian12
WORKDIR /app
COPY --from=build /out/keyserver /app/keyserver
COPY --from=build /src/index.html /app/index.html
COPY --chown=nonroot:nonroot --from=build /src/keys.json /data/keys.json
ENV KEYSERVER_DATA_FILE=/data/keys.json
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app/keyserver"]
