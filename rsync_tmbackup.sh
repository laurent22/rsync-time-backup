#!/usr/bin/env bash

APPNAME=$(basename $0 | sed "s/\.sh//")

############################# Log functions ###################################

fn_log_info()  { echo "$APPNAME: $1"; }
fn_log_warn()  { echo "$APPNAME: [WARNING] $1"; }
fn_log_error() { echo "$APPNAME: [ERROR] $1"; }

######## Make sure everything really stops when CTRL+C is pressed #############

fn_terminate_script() {
	fn_log_info "SIGINT caught."
	exit 1
}

trap 'fn_terminate_script' SIGINT

######### Small utility functions for reducing code duplication ###############

fn_find_backups() {
	# List backups newest first.
	find "$DEST_FOLDER" -type d -name "????-??-??-??????" -prune | sort -r
}

fn_expire_backup() {
	# Double-check that we're on a backup destination to be completely
	# sure we're deleting the right folder
	if [ -z "$(fn_find_backup_marker "$(dirname -- "$1")")" ]; then
		fn_log_error "$1 is not on a backup destination - aborting."
		exit 1
	fi

	fn_log_info "Expiring $1"
	rm -rf -- "$1"
}

################### Source and destination information ########################

SRC_FOLDER=${1%/}
DEST_FOLDER=${2%/}
EXCLUSION_FILE=$3

for ARG in "$SRC_FOLDER" "$DEST_FOLDER" "$EXCLUSION_FILE"; do
	if [[ "$ARG" == *"'"* ]]; then
		fn_log_error 'Arguments may not have any single quote characters.'
		exit 1
	fi
done

if [ -n "$EXCLUSION_FILE" ]; then
	EXCLUDES_OPTION="--exclude-from '$EXCLUSION_FILE'"
fi

########### Check that the destination drive is a backup drive ################

# TODO: check that the destination supports hard links

fn_backup_marker_path() { echo "$1/backup.marker"; }
fn_find_backup_marker() { find "$(fn_backup_marker_path "$1")" 2>/dev/null; }

if [ -z "$(fn_find_backup_marker "$DEST_FOLDER")" ]; then
	fn_log_info "Destination does not appear to be a backup folder or drive (marker file not found)."
	fn_log_info "If you wish to make your backups here, please run this command:"
	fn_log_info ""
	fn_log_info "touch \"$(fn_backup_marker_path "$DEST_FOLDER")\""
	exit 1
fi

####################### Setup additional variables ############################

# Date logic
NOW=$(date +"%Y-%m-%d-%H%M%S")

export IFS=$'\n' # Better for handling spaces in filenames.
DEST="$DEST_FOLDER/$NOW"
PREVIOUS_DEST="$(fn_find_backups | head -n 1)"
INPROGRESS_FILE="$DEST_FOLDER/backup.inprogress"

##### Handle case where a previous backup failed or was interrupted. ##########

if [ -f "$INPROGRESS_FILE" ]; then
	if [ -n "$PREVIOUS_DEST" ]; then
		# - Last backup is moved to current backup folder so that it can be resumed.
		# - 2nd to last backup becomes last backup.
		fn_log_info "Previous backup failed or was interrupted. Resuming..."
		mv -- "$PREVIOUS_DEST" "$DEST"
		PREVIOUS_DEST="$(fn_find_backups | sed -n '2p')"
	fi
fi

############# Make directories if they haven't been already. ##################

mkdir -pv -- "$DEST"

################# Determine if this backup is incremental ######################

if [ -z "$PREVIOUS_DEST" ]; then
	fn_log_info "No previous backup - creating new one."
else
	fn_log_info "Previous backup found - doing incremental backup from $PREVIOUS_DEST"
	LINK_DEST_OPTION="--link-dest='$PREVIOUS_DEST'"
fi

CMD="rsync \
--compress \
--numeric-ids \
--links \
--hard-links \
--delete \
--delete-excluded \
--one-file-system \
--archive \
--itemize-changes \
--verbose \
--log-file '$INPROGRESS_FILE' \
$EXCLUDES_OPTION \
$LINK_DEST_OPTION \
-- '$SRC_FOLDER/' '$DEST/' \
| grep -E '^deleting|[^/]$'"


while : ; do
######### Purge certain old backups before beginning new backup. ##############

	# Default value for $PREV ensures that the most recent backup is never deleted.
	PREV="0000-00-00-000000"
	COUNTER=0
	for FILENAME in $(fn_find_backups); do
		BACKUP_DATE=$(basename "$FILENAME")

		if   [ $COUNTER -le 24 ]; then
			: # Always keep the 24 newest backups.
		elif [ $COUNTER -le 54 ]; then
			# Delete all but the most recent of each day.
			[ "${BACKUP_DATE:0:10}" == "${PREV:0:10}" ] && fn_expire_backup "$FILENAME"
		else
			# Delete all but the most recent of each month.
			[ "${BACKUP_DATE:0:7}" == "${PREV:0:7}" ] && fn_expire_backup "$FILENAME"
		fi

		PREV=$BACKUP_DATE
		let COUNTER+=1
	done

############################## Start backup ###################################

	fn_log_info "Starting backup..."
	fn_log_info "From: $SRC_FOLDER"
	fn_log_info "To:   $DEST"

	fn_log_info "Running command:"
	fn_log_info "$CMD"

	eval $CMD
	RSYNC_EXIT_CODE=$?

###################### Check if we ran out of space ###########################

	# TODO: find better way to check for out of space condition without parsing log.
	NO_SPACE_LEFT="$(grep "No space left on device (28)\|Result too large (34)" "$INPROGRESS_FILE")"

	if [ -n "$NO_SPACE_LEFT" ]; then
		fn_log_warn "No space left on device - removing oldest backup and resuming."

		if [[ "$(fn_find_backups | wc -l)" -lt "2" ]]; then
			fn_log_error "No space left on device, and no old backup to delete."
			exit 1
		fi

		fn_expire_backup "$(fn_find_backups | tail -n 1)"

		# Resume backup
		continue
	fi

	if [ "$RSYNC_EXIT_CODE" != "0" ]; then
		fn_log_error "Exited with error code $RSYNC_EXIT_CODE"
		exit $RSYNC_EXIT_CODE
	fi

################# Add symlink to last successful backup #######################

	rm -rf -- "$DEST_FOLDER/latest"
	ln -vs -- "$NOW" "$DEST_FOLDER/latest"

	rm -- "$INPROGRESS_FILE"
	# TODO: grep for "^rsync error:.*$" in log
	fn_log_info "Backup completed without errors."
	exit 0
done
