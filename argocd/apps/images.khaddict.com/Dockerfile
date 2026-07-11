FROM alpine:3.24 AS builder
RUN apk add --no-cache vips-tools imagemagick
COPY images/ /data/
COPY process-icons.sh /tmp/process-icons.sh
RUN chmod +x /tmp/process-icons.sh && /tmp/process-icons.sh && rm -f /data/icons/no-outline
RUN mkdir -p /data/icons/thumbs /data/gallery/thumbs \
 && find /data/icons -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
      -exec sh -c 'vipsthumbnail "$1" --size 90x90 -o "/data/icons/thumbs/$(basename "$1")"' _ {} \; \
 && find /data/gallery -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) \
      -exec sh -c 'vipsthumbnail "$1" --size 800x600 --crop=centre -o "/data/gallery/thumbs/$(basename "$1")[Q=80]"' _ {} \;

FROM nginx:1.31.2
COPY --from=builder /data/ /data/
