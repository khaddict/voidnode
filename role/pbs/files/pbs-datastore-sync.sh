#!/usr/bin/env bash
set -euo pipefail

SRC="${PBS_SYNC_SOURCE:-/datastore}"
DST_ROOT="${PBS_SYNC_DEST:-kdrive:voidnode}"
KEEP_RECENT="${PBS_SYNC_KEEP_RECENT:-4}"
KEEP_MONTHLY="${PBS_SYNC_KEEP_MONTHLY:-6}"
KEEP_YEARLY="${PBS_SYNC_KEEP_YEARLY:-1}"

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
echo "  Retention:   ${KEEP_RECENT} recent, ${KEEP_MONTHLY} monthly, ${KEEP_YEARLY} yearly"

/usr/bin/rclone sync "$SRC" "$DST" \
	--checkers 8 \
	--transfers 4 \
	--bwlimit=10M \
	--progress

echo "Backup completed: $DST"

mapfile -t BACKUPS < <(
	/usr/bin/rclone lsf "$DST_ROOT" --dirs-only | sed 's:/$::' | sort
)

declare -A KEEP_SET

# Recent: keep last KEEP_RECENT syncs
COUNT="${#BACKUPS[@]}"
RECENT_START=$(( COUNT - KEEP_RECENT ))
(( RECENT_START < 0 )) && RECENT_START=0
for (( i=RECENT_START; i<COUNT; i++ )); do
	KEEP_SET["${BACKUPS[$i]}"]=1
done

# Collect the last sync per month and per year (dirs are sorted ascending)
declare -A MONTHLY_REP
declare -A YEARLY_REP
for BACKUP in "${BACKUPS[@]}"; do
	YEAR="${BACKUP:0:4}"
	MONTH="${BACKUP:5:2}"
	MONTHLY_REP["${YEAR}-${MONTH}"]="$BACKUP"
	YEARLY_REP["$YEAR"]="$BACKUP"
done

C_YEAR=$(( 10#$(date +'%Y') ))
C_MONTH=$(( 10#$(date +'%m') ))

# Monthly: keep last sync of each month within KEEP_MONTHLY months
for KEY in "${!MONTHLY_REP[@]}"; do
	B_YEAR=$(( 10#${KEY:0:4} ))
	B_MONTH=$(( 10#${KEY:5:2} ))
	DIFF=$(( (C_YEAR - B_YEAR) * 12 + (C_MONTH - B_MONTH) ))
	if (( DIFF >= 0 && DIFF <= KEEP_MONTHLY )); then
		KEEP_SET["${MONTHLY_REP[$KEY]}"]=1
	fi
done

# Yearly: keep last sync of each year for KEEP_YEARLY years back
for YEAR in "${!YEARLY_REP[@]}"; do
	DIFF=$(( C_YEAR - 10#$YEAR ))
	if (( DIFF >= 1 && DIFF <= KEEP_YEARLY )); then
		KEEP_SET["${YEARLY_REP[$YEAR]}"]=1
	fi
done

# Prune anything not protected by a retention tier
PRUNED=0
for BACKUP in "${BACKUPS[@]}"; do
	if [[ -z "${KEEP_SET[$BACKUP]+x}" ]]; then
		echo "Pruning: ${DST_ROOT}/${BACKUP}"
		/usr/bin/rclone purge "${DST_ROOT}/${BACKUP}"
		PRUNED=$(( PRUNED + 1 ))
	fi
done

echo "Done. Pruned ${PRUNED} old backup(s), keeping ${#KEEP_SET[@]}."
