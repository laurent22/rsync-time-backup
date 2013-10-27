#!/bin/bash

# -----------------------------------------------------------------------------
# Make sure everything really stops when CTRL+C is pressed
# -----------------------------------------------------------------------------

terminate_script() {
	echo "SIGINT caught"
	exit 1
}

trap 'terminate_script' SIGINT

# -----------------------------------------------------------------------------
# Source and destination information
# -----------------------------------------------------------------------------

SRC_FOLDER=${1%/}
DEST_FOLDER=${2%/}
EXCLUSION_FILE=$3

# -----------------------------------------------------------------------------
# Check that the destination drive is a backup drive
# -----------------------------------------------------------------------------

DEST_MARKER_FILE=$DEST_FOLDER/backup.marker
if [ ! -f "$DEST_MARKER_FILE" ]; then
	echo "Safety check failed - the destination does not appear to be a backup folder or drive (marker file not found)."
	echo "If it is indeed a backup folder, you may add the marker file by running the following command:"
	echo ""
	echo "touch \"$DEST_MARKER_FILE\""
	echo ""
	exit 1
fi

# -----------------------------------------------------------------------------
# Setup additional variables
# -----------------------------------------------------------------------------

NOW=$(date +"%Y-%m-%d-%H%M%S")
DEST=$DEST_FOLDER/$NOW
LAST_TIME=$(ls -1 $DEST_FOLDER | grep "\d\d\d\d-\d\d-\d\d-\d\d\d\d\d\d" | tail -n 1)
PREVIOUS_DEST=$DEST_FOLDER/$LAST_TIME
INPROGRESS_FILE=$DEST_FOLDER/backup.inprogress

# -----------------------------------------------------------------------------
# Handle case where a previous backup failed or was interrupted.
# -----------------------------------------------------------------------------

if [ -f "$INPROGRESS_FILE" ]; then
	if [ "$LAST_TIME" != "" ]; then
		# - Last backup is moved to current backup folder so that it can be resumed.
		# - 2nd to last backup becomes last backup.
		echo "$INPROGRESS_FILE already exists - the previous backup failed or was interrupted. Backup will resume from there."
		LINE_COUNT=$(ls -1 $DEST_FOLDER | grep "\d\d\d\d-\d\d-\d\d-\d\d\d\d\d\d" | tail -n 2 | wc -l)
		mv $PREVIOUS_DEST $DEST
		if [ "$LINE_COUNT" -gt 1 ]; then
			SECOND_LAST_TIME=$(ls -1 $DEST_FOLDER | grep "\d\d\d\d-\d\d-\d\d-\d\d\d\d\d\d" | tail -n 2 | head -n 1)
			LAST_TIME=$SECOND_LAST_TIME
		else
			LAST_TIME=""
		fi
		PREVIOUS_DEST=$DEST_FOLDER/$LAST_TIME
	fi
fi

# -----------------------------------------------------------------------------
# Check if we are doing an incremental backup (if previous backup exists) or not
# -----------------------------------------------------------------------------

LINK_DEST_OPTION=""
if [ "$LAST_TIME" == "" ]; then
	echo "No previous backup - creating new one."
else
	# If the path is relative, it needs to be relative to the destination. To keep
	# it simple, just use an absolute path. See http://serverfault.com/a/210058/118679
	PREVIOUS_DEST=`cd \`dirname "$PREVIOUS_DEST"\`; pwd`"/"`basename "$PREVIOUS_DEST"`
	echo "Previous backup found - doing incremental backup from $PREVIOUS_DEST"
	LINK_DEST_OPTION="--link-dest=$PREVIOUS_DEST"
fi

# -----------------------------------------------------------------------------
# Create destination folder if it doesn't already exists
# -----------------------------------------------------------------------------

if [ ! -d "$DEST" ]; then
	echo "Creating destination $DEST"
	mkdir -p $DEST
fi

# -----------------------------------------------------------------------------
# Start backup
# -----------------------------------------------------------------------------

echo "Starting backup..."
echo "From: $SRC_FOLDER"
echo "To:   $DEST"

CMD="rsync"
CMD="$CMD --compress"
CMD="$CMD --numeric-ids"
CMD="$CMD --links"
CMD="$CMD --hard-links"
CMD="$CMD --delete"
CMD="$CMD --delete-excluded"
CMD="$CMD --archive"
CMD="$CMD --progress"
if [ "$EXCLUSION_FILE" != "" ]; then
	CMD="$CMD --exclude-from \"$EXCLUSION_FILE\""
fi
CMD="$CMD $LINK_DEST_OPTION $SRC_FOLDER/ $DEST/"
CMD="$CMD | grep -E '^deleting|[^/]$'"

echo "Running command:"
echo $CMD

touch $INPROGRESS_FILE
eval $CMD
EXIT_CODE=$?
if [ "$EXIT_CODE" == "0" ]; then
	rm $INPROGRESS_FILE
else
	echo "Error: Exited with error code $EXIT_CODE"
fi
