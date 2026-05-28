#!/usr/bin/env bash
set -euo pipefail

SRC="${PBS_SYNC_SOURCE:-/datastore}"
DST_ROOT="${PBS_SYNC_DEST:-kdrive:voidnode}"
KEEP="${PBS_SYNC_KEEP:-5}"

TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
DST="${DST_ROOT}/${TIMESTAMP}"

if [[ ! -d "$SRC" ]]; then
	echo "Source directory '$SRC' does not exist." >&2
	exit 1
fi

if ! command -v rclone >/dev/null 2>&1; then
	echo "rclone is not installed or not in PATH." >&2
	exit 1
fi

echo "Starting backup:"
echo "  Source:      $SRC"
echo "  Destination: $DST"
echo "  Keep:        $KEEP versions"

/usr/bin/rclone sync "$SRC" "$DST" \
	--checkers 8 \
	--transfers 4 \
	--bwlimit=10M \
	--progress

echo "Backup completed: $DST"

mapfile -t BACKUPS < <(
	/usr/bin/rclone lsf "$DST_ROOT" --dirs-only | sed 's:/$::' | sort
)

COUNT="${#BACKUPS[@]}"

if (( COUNT > KEEP )); then
	DELETE_COUNT=$((COUNT - KEEP))

	echo "Pruning old backups: deleting $DELETE_COUNT old version(s)"

	for OLD_BACKUP in "${BACKUPS[@]:0:DELETE_COUNT}"; do
		echo "Deleting old backup: ${DST_ROOT}/${OLD_BACKUP}"
		/usr/bin/rclone purge "${DST_ROOT}/${OLD_BACKUP}"
	done
else
	echo "No old backups to delete. Current versions: $COUNT"
fi

echo "Done."
