FROM alpine:3.21 AS builder
RUN apk add --no-cache vips-tools
COPY images/ /data/
RUN mkdir -p /data/icons/thumbs /data/gallery/thumbs \
 && find /data/icons -maxdepth 1 -type f \
      -exec sh -c 'vipsthumbnail "$1" --size 90x90 -o "/data/icons/thumbs/$(basename "$1")"' _ {} \; \
 && find /data/gallery -maxdepth 1 -type f \
      -exec sh -c 'vipsthumbnail "$1" --size 90x90 --crop=centre -o "/data/gallery/thumbs/$(basename "$1")[Q=75]"' _ {} \;

FROM nginx:1.31.2
COPY --from=builder /data/ /data/
