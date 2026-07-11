#!/bin/sh
# Adds a white sticker-style outline to every icon, then normalizes it to
# 138x138 (the site's display size). Border thickness scales with the
# source resolution so a full-HD source and an already-small source both
# end up with a proportionate outline.
#
# Icons listed (one filename per line, e.g. "github.png") in no-outline
# are resized like the rest but skip the outline step.
set -eu

TARGET=138
SKIP_LIST=/data/icons/no-outline

is_skipped() {
  [ -f "$SKIP_LIST" ] || return 1
  grep -qx "$1" "$SKIP_LIST"
}

for f in /data/icons/*; do
  [ -f "$f" ] || continue
  case "$f" in
    *.png|*.jpg|*.jpeg) ;;
    *) continue ;;
  esac

  name=$(basename "$f")

  if is_skipped "$name"; then
    magick "$f" -filter Lanczos \
      -resize "512x512>" -resize "256x256>" -resize "${TARGET}x${TARGET}>" \
      -unsharp 0x0.8+0.6+0.02 -define png:color-type=6 "$f"
    continue
  fi

  width=$(magick identify -format '%w' "$f")
  radius=$(( width * 16 / 1000 ))
  [ "$radius" -lt 2 ] && radius=2

  # Pad with transparent margin first: if the source content already
  # touches the canvas edge, dilating without headroom clips the outline.
  magick "$f" -bordercolor none -border "$radius" /tmp/padded.png
  padded_width=$(magick identify -format '%w' /tmp/padded.png)

  magick /tmp/padded.png -alpha extract /tmp/mask.png
  magick /tmp/mask.png -morphology Dilate Disk:"$radius" /tmp/mask_dilated.png
  magick -size "${padded_width}x${padded_width}" xc:white /tmp/mask_dilated.png -alpha off \
    -compose CopyOpacity -composite -define png:color-type=6 /tmp/outline.png
  magick /tmp/outline.png /tmp/padded.png -compose over -composite -define png:color-type=6 /tmp/sticker.png

  magick /tmp/sticker.png -filter Lanczos \
    -resize "512x512>" -resize "256x256>" -resize "${TARGET}x${TARGET}>" \
    -unsharp 0x0.8+0.6+0.02 -define png:color-type=6 "$f"

  rm -f /tmp/padded.png /tmp/mask.png /tmp/mask_dilated.png /tmp/outline.png /tmp/sticker.png
done
