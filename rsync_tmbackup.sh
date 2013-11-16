#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# Log functions
# -----------------------------------------------------------------------------

fn_log_info() {
	echo "rsync_tmbackup: $1"
}

fn_log_warn() {
	echo "rsync_tmbackup: [WARNING] $1"
}

fn_log_error() {
	echo "rsync_tmbackup: [ERROR] $1"
}

# -----------------------------------------------------------------------------
# Make sure everything really stops when CTRL+C is pressed
# -----------------------------------------------------------------------------

fn_terminate_script() {
	echo "rsync_tmbackup: SIGINT caught."
	exit 1
}

trap 'fn_terminate_script' SIGINT

# -----------------------------------------------------------------------------
# Small utility functions for reducing code duplication
# -----------------------------------------------------------------------------

fn_parse_date() {
	# Converts YYYY-MM-DD-HHMMSS to YYYY-MM-DD HH:MM:SS and then to Unix Epoch.
	case "$OSTYPE" in
		linux*) date -d "${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}" +%s ;;
		darwin*) date -j -f "%Y-%m-%d-%H%M%S" "$1" "+%s" ;;
	esac
}

fn_find_backups() {
	# List backups newest first.
	find "$DEST_FOLDER" -type d -name "????-??-??-??????" -prune | sort -r
}

fn_expire_backup() {
	# Double-check that we're on a backup destination to be completely
	# sure we're deleting the right folder
	if [ -z "$(fn_is_backup_destination "$(dirname -- "$1")")" ]; then
		fn_log_error "$1 is not on a backup destination - aborting."
		exit 1
	fi

	fn_log_info "Expiring $1"
	rm -rf -- "$1"
}

# -----------------------------------------------------------------------------
# Source and destination information
# -----------------------------------------------------------------------------

SRC_FOLDER=${1%/}
DEST_FOLDER=${2%/}
EXCLUSION_FILE=$3

for arg in "$SRC_FOLDER" "$DEST_FOLDER" "$EXCLUSION_FILE"; do
	if [[ "$arg" == *"'"* ]]; then
		fn_log_error 'Arguments may not have any single quote characters.'
		exit 1
	fi
done

# -----------------------------------------------------------------------------
# Check that the destination drive is a backup drive
# -----------------------------------------------------------------------------

# TODO: check that the destination supports hard links

fn_backup_marker_path() {
	echo "$1/backup.marker"
}

fn_is_backup_destination() {
	find "$(fn_backup_marker_path "$1")" 2>/dev/null
}

if [ -z "$(fn_is_backup_destination $DEST_FOLDER)" ]; then
	fn_log_info "Safety check failed - the destination does not appear to be a backup folder or drive (marker file not found)."
	fn_log_info "If it is indeed a backup folder, you may add the marker file by running the following command:"
	fn_log_info ""
	fn_log_info "touch \"$(fn_backup_marker_path $DEST_FOLDER)\""
	fn_log_info ""
	exit 1
fi

# -----------------------------------------------------------------------------
# Setup additional variables
# -----------------------------------------------------------------------------

# Date logic
NOW=$(date +"%Y-%m-%d-%H%M%S")
EPOCH=$(date "+%s")
KEEP_ALL_DATE=$(($EPOCH - 86400))       # 1 day ago
KEEP_DAILIES_DATE=$(($EPOCH - 2678400)) # 31 days ago


export IFS=$'\n' # Better for handling spaces in filenames.
PROFILE_FOLDER="$HOME/.rsync_tmbackup"
LOG_FILE="$PROFILE_FOLDER/$NOW.log"
DEST=$DEST_FOLDER/$NOW
PREVIOUS_DEST=$(fn_find_backups | head -n 1)
INPROGRESS_FILE=$DEST_FOLDER/backup.inprogress

mkdir -pv -- "$PROFILE_FOLDER"

# -----------------------------------------------------------------------------
# Handle case where a previous backup failed or was interrupted.
# -----------------------------------------------------------------------------

if [ -f "$INPROGRESS_FILE" ]; then
	if [ "$PREVIOUS_DEST" != "" ]; then
		# - Last backup is moved to current backup folder so that it can be resumed.
		# - 2nd to last backup becomes last backup.
		fn_log_info "$INPROGRESS_FILE already exists - the previous backup failed or was interrupted. Backup will resume from there."
		mv -- "$PREVIOUS_DEST" "$DEST"
		PREVIOUS_DEST="$(fn_find_backups | sed -n '2p')"
	fi
fi

# Run in a loop to handle the "No space left on device" logic.
while [ "1" ]; do

	# -----------------------------------------------------------------------------
	# Check if we are doing an incremental backup (if previous backup exists) or not
	# -----------------------------------------------------------------------------

	LINK_DEST_OPTION=""
	if [ "$PREVIOUS_DEST" == "" ]; then
		fn_log_info "No previous backup - creating new one."
	else
		fn_log_info "Previous backup found - doing incremental backup from $PREVIOUS_DEST"
		LINK_DEST_OPTION="--link-dest=$PREVIOUS_DEST"
	fi

	# -----------------------------------------------------------------------------
	# Create destination folder if it doesn't already exists
	# -----------------------------------------------------------------------------

	mkdir -pv -- "$DEST"

	# -----------------------------------------------------------------------------
	# Purge certain old backups before beginning new backup.
	# -----------------------------------------------------------------------------

	# Default value for $prev ensures that the most recent backup is never deleted.
	prev="0000-00-00-000000"
	for fname in $(fn_find_backups); do
		date=$(basename "$fname")
		stamp=$(fn_parse_date $date)

		# Skip if failed to parse date...
		[ -n "$stamp" ] || continue

		if   [ $stamp -ge $KEEP_ALL_DATE ]; then
			true

		elif [ $stamp -ge $KEEP_DAILIES_DATE ]; then
			# Delete all but the most recent of each day.
			[ "${date:0:10}" == "${prev:0:10}" ] && fn_expire_backup "$fname"

		else
			# Delete all but the most recent of each month.
			[ "${date:0:7}" == "${prev:0:7}" ] && fn_expire_backup "$fname"
		fi

		prev=$date
	done

	# -----------------------------------------------------------------------------
	# Start backup
	# -----------------------------------------------------------------------------

	LOG_FILE="$PROFILE_FOLDER/$(date +"%Y-%m-%d-%H%M%S").log"

	fn_log_info "Starting backup..."
	fn_log_info "From: $SRC_FOLDER"
	fn_log_info "To:   $DEST"

	CMD="rsync"
	CMD="$CMD --compress"
	CMD="$CMD --numeric-ids"
	CMD="$CMD --links"
	CMD="$CMD --hard-links"
	CMD="$CMD --delete"
	CMD="$CMD --delete-excluded"
	CMD="$CMD --one-file-system"
	CMD="$CMD --archive"
	CMD="$CMD --itemize-changes"
	CMD="$CMD --verbose"
	CMD="$CMD --log-file '$LOG_FILE'"
	if [ "$EXCLUSION_FILE" != "" ]; then
		# We've already checked that $EXCLUSION_FILE doesn't contain a single quote
		CMD="$CMD --exclude-from '$EXCLUSION_FILE'"
	fi
	CMD="$CMD $LINK_DEST_OPTION"
	CMD="$CMD -- '$SRC_FOLDER/' '$DEST/'"
	CMD="$CMD | grep -E '^deleting|[^/]$'"

	fn_log_info "Running command:"
	fn_log_info "$CMD"

	touch -- "$INPROGRESS_FILE"
	eval $CMD
	RSYNC_EXIT_CODE=$?

	# -----------------------------------------------------------------------------
	# Check if we ran out of space
	# -----------------------------------------------------------------------------

	# TODO: find better way to check for out of space condition without parsing log.
	grep --quiet "No space left on device (28)" "$LOG_FILE"
	NO_SPACE_LEFT="$?"
	if [ "$NO_SPACE_LEFT" != "0" ]; then
		# This error might also happen if there is no space left
		grep --quiet "Result too large (34)" "$LOG_FILE"
		NO_SPACE_LEFT="$?"
	fi

	rm -- "$LOG_FILE"

	if [ "$NO_SPACE_LEFT" == "0" ]; then
		# TODO: -y flag
		read -p "It looks like there is no space left on the destination. Delete old backup? (Y/n) " yn
		case $yn in
			[Nn]* ) exit 0;;
		esac

		fn_log_warn "No space left on device - removing oldest backup and resuming."

		BACKUP_FOLDER_COUNT=$(fn_find_backups | wc -l)
		if [ "$BACKUP_FOLDER_COUNT" -lt "2" ]; then
			fn_log_error "No space left on device, and no old backup to delete."
			exit 1
		fi

		OLD_BACKUP_PATH=$(fn_find_backups | tail -n 1)
		if [ "$OLD_BACKUP_PATH" == "" ]; then
			fn_log_error "No space left on device, and cannot get path to oldest backup to delete."
			exit 1
		fi

		fn_expire_backup "$OLD_BACKUP_PATH"

		# Resume backup
		continue
	fi

	if [ "$RSYNC_EXIT_CODE" != "0" ]; then
		fn_log_error "Exited with error code $RSYNC_EXIT_CODE"
		exit $RSYNC_EXIT_CODE
	fi

	# -----------------------------------------------------------------------------
	# Add symlink to last successful backup
	# -----------------------------------------------------------------------------

	cd "$DEST_FOLDER"
	rm -f -- "latest"
	ln -s -- $(basename -- "$DEST") "latest"
	cd -

	rm -- "$INPROGRESS_FILE"
	# TODO: grep for "^rsync error:.*$" in log
	fn_log_info "Backup completed without errors."
	exit 0
done
