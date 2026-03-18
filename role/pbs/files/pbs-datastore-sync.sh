#!/usr/bin/env bash
set -euo pipefail

SRC="${PBS_SYNC_SOURCE:-/datastore}"
DST="${PBS_SYNC_DEST:-shadowDrive:voidnode}"

if [[ ! -d "$SRC" ]]; then
	echo "Source directory '$SRC' does not exist." >&2
	exit 1
fi

if ! command -v rclone >/dev/null 2>&1; then
	echo "rclone is not installed or not in PATH." >&2
	exit 1
fi

/usr/bin/rclone sync "$SRC" "$DST" --checkers 8 --transfers 4 --bwlimit=10M --progress
