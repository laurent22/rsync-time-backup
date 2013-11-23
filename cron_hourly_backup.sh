#!/bin/bash
#
# Installation instructions:
#
# 1. Declare where you installed rsync_tmbackup.sh to:

TMBACKUP="/usr/local/bin/rsync_tmbackup.sh"

# 2. Copy this script to /etc/cron.hourly
#
# 3. Run `sudo chmod 755 /etc/cron.hourly/cron_hourly_backup.sh`
#

#           Ubuntu      Fedora
for DEST in /media/*/*/ /run/media/*/*/; do
    [ -f "$DEST/backup.marker" ] || continue
    USERNAME=$(basename $(dirname "$DEST"))
    EXCLUDES=$(find "/home/$USERNAME/.backup.excludes" 2>/dev/null)
    bash "$TMBACKUP" "/home/$USERNAME" "$DEST" "$EXCLUDES"
done
