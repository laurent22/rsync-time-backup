#!/usr/bin/env bash

APPNAME=$(basename "$0" | sed "s/\.sh$//")

# -----------------------------------------------------------------------------
# Log functions
# -----------------------------------------------------------------------------

fn_log_info()  { echo "$APPNAME: $1"; }
fn_log_warn()  { echo "$APPNAME: [WARNING] $1" 1>&2; }
fn_log_error() { echo "$APPNAME: [ERROR] $1" 1>&2; }
fn_log_info_cmd()  {
        if [ -n "$SSH_DEST_FOLDER_PREFIX" ]; then
                echo "$APPNAME: $SSH_CMD '$1'";
        else
                echo "$APPNAME: $1";
        fi
}

# -----------------------------------------------------------------------------
# Make sure everything really stops when CTRL+C is pressed
# -----------------------------------------------------------------------------

fn_terminate_script() {
        fn_log_info "SIGINT caught."
        exit 1
}

trap 'fn_terminate_script' SIGINT

# -----------------------------------------------------------------------------
# Prune backups byu number
# -----------------------------------------------------------------------------
fn_prune_backups() {
    local backup_count=$(fn_find_backups | wc -l)

    while [ "$backup_count" -gt "$MAX_BACKUPS" ]; do
        local oldest_backup=$(fn_find_backups | tail -n 1)
        fn_log_info "Pruning oldest backup: $oldest_backup"
        fn_expire_backup "$oldest_backup"

        # Verificar y corregir permisos después de eliminar un backup
        local parent_dir=$(dirname "$oldest_backup")
        fn_run_cmd "chmod 700 '$parent_dir'"
        if ! fn_run_cmd "chmod 700 '$parent_dir'"; then
          fn_log_error "Failed to set permissions on parent directory: $parent_dir"
          exit 1
        fi

        backup_count=$(fn_find_backups | wc -l)
    done
}


# -----------------------------------------------------------------------------
# Small utility functions for reducing code duplication
# -----------------------------------------------------------------------------
fn_display_usage() {
        echo "Usage: $(basename "$0") [OPTION]... <[USER@HOST:]SOURCE> <[USER@HOST:]DESTINATION> [exclude-pattern-file]"
        echo ""
        echo "Options"
        echo " -p, --port             SSH port."
        echo " -h, --help             Display this help message."
        echo " -i, --id_rsa           Specify the private ssh key to use."
        echo " --rsync-get-flags      Display the default rsync flags that are used for backup. If using remote"
        echo "                        drive over SSH, --compress will be added."
        echo " --rsync-set-flags      Set the rsync flags that are going to be used for backup."
        echo " --rsync-append-flags   Append the rsync flags that are going to be used for backup."
        echo " --log-dir              Set the log file directory. If this flag is set, generated files will"
        echo "                        not be managed by the script - in particular they will not be"
        echo "                        automatically deleted."
        echo "                        Default: $LOG_DIR"
        echo " --log-to-destination   Store logs in the destination folder under .$APPNAME/"
        echo " --strategy             Set the expiration strategy. Default: \"1:1 30:7 365:30\" means after one"
        echo "                        day, keep one backup per day. After 30 days, keep one backup every 7 days."
        echo "                        After 365 days keep one backup every 30 days."
        echo " --no-auto-expire       Disable automatically deleting backups when out of space. Instead an error"
        echo "                        is logged, and the backup is aborted."
        echo " -m, --max_backups N    Specify the maximum number of backups (default: 10)."
        echo "                        After this number of backups, script prune backups."
        echo " --sudo              script has not run sudo"
        echo ""
        echo "For more detailed help, please see the README file:"
        echo ""
        echo "https://gitlab.castris.com/root/rsync-time-backup"
}

fn_parse_date() {
        # Converts YYYY-MM-DD-HHMMSS to YYYY-MM-DD HH:MM:SS and then to Unix Epoch.
        case "$OSTYPE" in
                linux*|cygwin*|netbsd*)
                        date -d "${1:0:10} ${1:11:2}:${1:13:2}:${1:15:2}" +%s ;;
                FreeBSD*) date -j -f "%Y-%m-%d-%H%M%S" "$1" "+%s" ;;
                darwin*)
                        # Under MacOS X Tiger
                        # Or with GNU 'coreutils' installed (by homebrew)
                        #   'date -j' doesn't work, so we do this:
                        yy=$(expr ${1:0:4})
                        mm=$(expr ${1:5:2} - 1)
                        dd=$(expr ${1:8:2})
                        hh=$(expr ${1:11:2})
                        mi=$(expr ${1:13:2})
                        ss=$(expr ${1:15:2})
                        perl -e 'use Time::Local; print timelocal('$ss','$mi','$hh','$dd','$mm','$yy'),"\n";' ;;
        esac
}

fn_find_backups() {
        fn_run_cmd "find "$DEST_FOLDER/" -maxdepth 1 -type d -name \"????-??-??-??????\" -prune | sort -r"
}

fn_expire_backup() {
        # Double-check that we're on a backup destination to be completely
        # sure we're deleting the right folder
        if [ -z "$(fn_find_backup_marker "$(dirname "$1")")" ]; then
                fn_log_error "$1 is not on a backup destination - aborting."
                exit 1
        fi

        fn_log_info "Expiring $1"
        # Sanitize permissions before deletion: snapshots may contain files/dirs
        # without owner write bit (e.g. ISPConfig .php-fcgi-starter at 0500,
        # web1/ at 0550) that would make `rm -rf` fail. Only safe on local dest.
        if [ -z "$SSH_DEST_FOLDER_PREFIX" ]; then
                fn_fix_permissions "$1"
        fi
        fn_rm_dir "$1"
}

fn_expire_backups() {
        local current_timestamp=$EPOCH
        local last_kept_timestamp=9999999999

        # we will keep requested backup
        backup_to_keep="$1"
        # we will also keep the oldest backup
        oldest_backup_to_keep="$(fn_find_backups | sort | sed -n '1p')"

        # Process each backup dir from the oldest to the most recent
        for backup_dir in $(fn_find_backups | sort); do

                local backup_date=$(basename "$backup_dir")
                local backup_timestamp=$(fn_parse_date "$backup_date")

                # Skip if failed to parse date...
                if [ -z "$backup_timestamp" ]; then
                        fn_log_warn "Could not parse date: $backup_dir"
                        continue
                fi

                if [ "$backup_dir" == "$backup_to_keep" ]; then
                        # this is the latest backup requsted to be kept. We can finish pruning
                        break
                fi

                if [ "$backup_dir" == "$oldest_backup_to_keep" ]; then
                        # We dont't want to delete the oldest backup. It becomes first "last kept" backup
                        last_kept_timestamp=$backup_timestamp
                        # As we keep it we can skip processing it and go to the next oldest one in the loop
                        continue
                fi

                # Find which strategy token applies to this particular backup
                for strategy_token in $(echo $EXPIRATION_STRATEGY | tr " " "\n" | sort -r -n); do
                        IFS=':' read -r -a t <<< "$strategy_token"

                        # After which date (relative to today) this token applies (X) - we use seconds to get exact cut off time
                        local cut_off_timestamp=$((current_timestamp - ${t[0]} * 86400))

                        # Every how many days should a backup be kept past the cut off date (Y) - we use days (not seconds)
                        local cut_off_interval_days=$((${t[1]}))

                        # If we've found the strategy token that applies to this backup
                        if [ "$backup_timestamp" -le "$cut_off_timestamp" ]; then

                                # Special case: if Y is "0" we delete every time
                                if [ $cut_off_interval_days -eq "0" ]; then
                                        fn_expire_backup "$backup_dir"
                                        break
                                fi

                                # we calculate days number since last kept backup
                                local last_kept_timestamp_days=$((last_kept_timestamp / 86400))
                                local backup_timestamp_days=$((backup_timestamp / 86400))
                                local interval_since_last_kept_days=$((backup_timestamp_days - last_kept_timestamp_days))

                                # Check if the current backup is in the interval between
                                # the last backup that was kept and Y
                                # to determine what to keep/delete we use days difference
                                if [ "$interval_since_last_kept_days" -lt "$cut_off_interval_days" ]; then

                                        # Yes: Delete that one
                                        fn_expire_backup "$backup_dir"
                                        # backup deleted no point to check shorter timespan strategies - go to the next backup
                                        break

                                else

                                        # No: Keep it.
                                        # this is now the last kept backup
                                        last_kept_timestamp=$backup_timestamp
                                        # and go to the next backup
                                        break
                                fi
                        fi
                done
        done
}

fn_parse_ssh() {
        # To keep compatibility with bash version < 3, we use grep
        if echo "$DEST_FOLDER"|grep -Eq '^[A-Za-z0-9\._%\+\-]+@[A-Za-z0-9.\-]+\:.+$'
        then
                SSH_USER=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\1/')
                SSH_HOST=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\2/')
                SSH_DEST_FOLDER=$(echo "$DEST_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\3/')
                if [ -n "$ID_RSA" ] ; then
                        SSH_CMD="ssh -p $SSH_PORT -i $ID_RSA ${SSH_USER}@${SSH_HOST}"
                else
                        SSH_CMD="ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST}"
                fi
                SSH_DEST_FOLDER_PREFIX="${SSH_USER}@${SSH_HOST}:"
        elif echo "$SRC_FOLDER"|grep -Eq '^[A-Za-z0-9\._%\+\-]+@[A-Za-z0-9.\-]+\:.+$'
        then
                SSH_USER=$(echo "$SRC_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\1/')
                SSH_HOST=$(echo "$SRC_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\2/')
                SSH_SRC_FOLDER=$(echo "$SRC_FOLDER" | sed -E  's/^([A-Za-z0-9\._%\+\-]+)@([A-Za-z0-9.\-]+)\:(.+)$/\3/')
                if [ -n "$ID_RSA" ] ; then
                        SSH_CMD="ssh -p $SSH_PORT -i $ID_RSA ${SSH_USER}@${SSH_HOST}"
                else
                        SSH_CMD="ssh -p $SSH_PORT ${SSH_USER}@${SSH_HOST}"
                fi
                SSH_SRC_FOLDER_PREFIX="${SSH_USER}@${SSH_HOST}:"
        fi
}

fn_run_cmd() {
        if [ -n "$SSH_DEST_FOLDER_PREFIX" ]
        then
                eval "$SSH_CMD '$1'"
        else
                eval $1
        fi
}

fn_run_cmd_src() {
        if [ -n "$SSH_SRC_FOLDER_PREFIX" ]
        then
                eval "$SSH_CMD '$1'"
        else
                eval $1
        fi
}

fn_find() {
        fn_run_cmd "find '$1'"  2>/dev/null
}

fn_get_absolute_path() {
        fn_run_cmd "cd '$1';pwd"
}

fn_mkdir() {
    if ! fn_run_cmd "mkdir -p '$1'"; then
        fn_log_error "Failed to create directory: $1"
        exit 1
    fi
    # Establecer permisos correctos
    if ! fn_run_cmd "chmod 700 '$1'"; then
        fn_log_error "Failed to set permissions on directory: $1"
        exit 1
    fi
}


# Removes a file or symlink - not for directories
fn_rm_file() {
        fn_run_cmd "rm -f '$1'"
}

fn_rm_dir() {
    if ! fn_run_cmd "rm -rf '$1'"; then
        fn_log_error "Failed to remove directory: $1"
        exit 1
    fi
}

fn_touch() {
        fn_run_cmd "touch '$1'"
}

fn_ln() {
        fn_run_cmd "ln -s '$1' '$2'"
}

fn_test_file_exists_src() {
        fn_run_cmd_src "test -e '$1'"
}

fn_df_t_src() {
        fn_run_cmd_src "df -T '${1}'"
}

fn_df_t() {
        fn_run_cmd "df -T '${1}'"
}

# Function to set permissions on a backup directory tree.
# Covers any dir or file lacking owner write (u+w) — this includes the legacy
# narrow cases (0111, 000) plus 0500/0550/0700/0710 typical of ISPConfig,
# /root/, /etc/ssl/private/, etc.
fn_fix_permissions() {
    local base_dir="$1"
    local sudo_cmd=""

    if [ "$SUDO" = true ]; then
        sudo_cmd="sudo"
    fi

    fn_log_info "Fixing permissions in directory: $base_dir"

    # Any dir without u+w → grant u+rwX so we can traverse and remove
    if ! find "$base_dir" -type d ! -perm -u=w -exec $sudo_cmd chmod u+rwX {} +; then
        fn_log_error "Failed to set permissions on some directories"
        exit 1
    fi
    # Any file without u+w → grant u+rw
    if ! find "$base_dir" -type f ! -perm -u=w -exec $sudo_cmd chmod u+rw {} +; then
        fn_log_error "Failed to set permissions on some files"
        exit 1
    fi

    fn_log_info "Permissions fixed successfully"
}

# -----------------------------------------------------------------------------
# Source and destination information
# -----------------------------------------------------------------------------
SSH_USER=""
SSH_HOST=""
SSH_DEST_FOLDER=""
SSH_SRC_FOLDER=""
SSH_CMD=""
SSH_DEST_FOLDER_PREFIX=""
SSH_SRC_FOLDER_PREFIX=""
SSH_PORT="22"
ID_RSA=""

SRC_FOLDER=""
DEST_FOLDER=""
EXCLUSION_FILE=""
LOG_DIR="$HOME/.$APPNAME"
AUTO_DELETE_LOG="1"
LOG_TO_DEST="0"
EXPIRATION_STRATEGY="1:1 30:7 365:30"
AUTO_EXPIRE="1"
## --perms --owner --group remove form flags
RSYNC_FLAGS="-D --numeric-ids --links --hard-links --one-file-system --itemize-changes --times --recursive --stats --human-readable"

MAX_BACKUPS="10"
SUDO=false

while :; do
        case $1 in
                -h|-\?|--help)
                        fn_display_usage
                        exit
                        ;;
                -p|--port)
                        shift
                        SSH_PORT=$1
                        ;;
                -i|--id_rsa)
                        shift
                        ID_RSA="$1"
                        ;;
                -m|--max_backups)
                        shift
                        MAX_BACKUPS=$1
                        ;;
                --rsync-get-flags)
                        shift
                        echo "$RSYNC_FLAGS"
                        exit
                        ;;
                --rsync-set-flags)
                        shift
                        RSYNC_FLAGS="$1"
                        ;;
                --rsync-append-flags)
                        shift
                        RSYNC_FLAGS="$RSYNC_FLAGS $1"
                        ;;
                --strategy)
                        shift
                        EXPIRATION_STRATEGY="$1"
                        ;;
                --log-dir)
                        shift
                        LOG_DIR="$1"
                        AUTO_DELETE_LOG="0"
                        ;;
                --log-to-destination)
                        LOG_TO_DEST="1"
                        AUTO_DELETE_LOG="0"
                        ;;
                --no-auto-expire)
                        AUTO_EXPIRE="0"
                        ;;
                --sudo)
                      SUDO=true
                      ;;
                --)
                        shift
                        SRC_FOLDER="$1"
                        DEST_FOLDER="$2"
                        EXCLUSION_FILE="$3"
                        break
                        ;;
                -*)
                        fn_log_error "Unknown option: \"$1\""
                        fn_log_info ""
                        fn_display_usage
                        exit 1
                        ;;
                *)
                        SRC_FOLDER="$1"
                        DEST_FOLDER="$2"
                        EXCLUSION_FILE="$3"
                        break
        esac

        shift
done

# Display usage information if required arguments are not passed
if [[ -z "$SRC_FOLDER" || -z "$DEST_FOLDER" ]]; then
        fn_display_usage
        exit 1
fi

# Strips off last slash from dest. Note that it means the root folder "/"
# will be represented as an empty string "", which is fine
# with the current script (since a "/" is added when needed)
# but still something to keep in mind.
# However, due to this behavior we delay stripping the last slash for
# the source folder until after parsing for ssh usage.

DEST_FOLDER="${DEST_FOLDER%/}"

fn_parse_ssh

if [ -n "$SSH_DEST_FOLDER" ]; then
        DEST_FOLDER="$SSH_DEST_FOLDER"
fi

if [ -n "$SSH_SRC_FOLDER" ]; then
        SRC_FOLDER="$SSH_SRC_FOLDER"
fi

# Exit if source folder does not exist.
if ! fn_test_file_exists_src "${SRC_FOLDER}"; then
        fn_log_error "Source folder \"${SRC_FOLDER}\" does not exist - aborting."
        exit 1
fi

# Now strip off last slash from source folder.
SRC_FOLDER="${SRC_FOLDER%/}"

for ARG in "$SRC_FOLDER" "$DEST_FOLDER" "$EXCLUSION_FILE"; do
        if [[ "$ARG" == *"'"* ]]; then
                fn_log_error 'Source and destination directories may not contain single quote characters.'
                exit 1
        fi
done

# -----------------------------------------------------------------------------
# Check that the destination drive is a backup drive
# -----------------------------------------------------------------------------

# TODO: check that the destination supports hard links

fn_backup_marker_path() { echo "$1/backup.marker"; }
fn_find_backup_marker() { fn_find "$(fn_backup_marker_path "$1")" 2>/dev/null; }

if [ -z "$(fn_find_backup_marker "$DEST_FOLDER")" ]; then
        fn_log_info "Safety check failed - the destination does not appear to be a backup folder or drive (marker file not found)."
        fn_log_info "If it is indeed a backup folder, you may add the marker file by running the following command:"
        fn_log_info ""
        fn_log_info_cmd "mkdir -p \"$DEST_FOLDER\" ; touch \"$(fn_backup_marker_path "$DEST_FOLDER")\""
        fn_log_info ""
        exit 1
fi

# Check source and destination file-system (df -T /dest).
# If one of them is FAT, use the --modify-window rsync parameter
# (see man rsync) with a value of 1 or 2.
#
# The check is performed by taking the second row
# of the output of the first command.
if [[ "$(fn_df_t_src "${SRC_FOLDER}" | awk '{print $2}' | grep -c -i -e "fat")" -gt 0 ]]; then
        fn_log_info "Source file-system is a version of FAT."
        fn_log_info "Using the --modify-window rsync parameter with value 2."
        RSYNC_FLAGS="${RSYNC_FLAGS} --modify-window=2"
elif [[ "$(fn_df_t "${DEST_FOLDER}" | awk '{print $2}' | grep -c -i -e "fat")" -gt 0 ]]; then
        fn_log_info "Destination file-system is a version of FAT."
        fn_log_info "Using the --modify-window rsync parameter with value 2."
        RSYNC_FLAGS="${RSYNC_FLAGS} --modify-window=2"
fi

# -----------------------------------------------------------------------------
# Setup additional variables
# -----------------------------------------------------------------------------

# Date logic
NOW=$(date +"%Y-%m-%d-%H%M%S")
EPOCH=$(date "+%s")
KEEP_ALL_DATE=$((EPOCH - 86400))       # 1 day ago
KEEP_DAILIES_DATE=$((EPOCH - 2678400)) # 31 days ago

export IFS=$'\n' # Better for handling spaces in filenames.
DEST="$DEST_FOLDER/$NOW"
PREVIOUS_DEST="$(fn_find_backups | head -n 1)"
INPROGRESS_FILE="$DEST_FOLDER/backup.inprogress"
MYPID="$$"

# -----------------------------------------------------------------------------
# Create log folder if it doesn't exist
# -----------------------------------------------------------------------------

if [[ $LOG_TO_DEST == "1" ]]; then
        LOG_DIR="$DEST_FOLDER/.$APPNAME"
fi

if [ ! -d "$LOG_DIR" ]; then
        fn_log_info "Creating log folder in '$LOG_DIR'..."
        mkdir "$LOG_DIR"
fi

# -----------------------------------------------------------------------------
# Handle case where a previous backup failed or was interrupted.
# -----------------------------------------------------------------------------

if [ -n "$(fn_find "$INPROGRESS_FILE")" ]; then
        if [ "$OSTYPE" == "cygwin" ]; then
                # 1. Grab the PID of previous run from the PID file
                RUNNINGPID="$(fn_run_cmd "cat $INPROGRESS_FILE")"

                # 2. Get the command for the process currently running under that PID and look for our script name
                RUNNINGCMD="$(procps -wwfo cmd -p $RUNNINGPID --no-headers | grep "$APPNAME")"

                # 3. Grab the exit code from grep (0=found, 1=not found)
                GREPCODE=$?

                # 4. if found, assume backup is still running
                if [ "$GREPCODE" = 0 ]; then
                        fn_log_error "Previous backup task is still active - aborting (command: $RUNNINGCMD)."
                        exit 1
                fi
        elif [[ "$OSTYPE" == "netbsd"* ]]; then
                RUNNINGPID="$(fn_run_cmd "cat $INPROGRESS_FILE")"
                if ps -axp "$RUNNINGPID" -o "command" | grep "$APPNAME" > /dev/null; then
                        fn_log_error "Previous backup task is still active - aborting."
                        exit 1
                fi
        else
                RUNNINGPID="$(fn_run_cmd "cat $INPROGRESS_FILE")"
                if ps -p "$RUNNINGPID" -o command | grep "$APPNAME"
                then
                        fn_log_error "Previous backup task is still active - aborting."
                        exit 1
                fi
        fi

        if [ -n "$PREVIOUS_DEST" ]; then
                # - Last backup is moved to current backup folder so that it can be resumed.
                # - 2nd to last backup becomes last backup.
                fn_log_info "$SSH_DEST_FOLDER_PREFIX$INPROGRESS_FILE already exists - the previous backup failed or was interrupted. Backup will resume from there."
                fn_run_cmd "mv $PREVIOUS_DEST $DEST"
                if [ "$(fn_find_backups | wc -l)" -gt 1 ]; then
                        PREVIOUS_DEST="$(fn_find_backups | sed -n '2p')"
                else
                        PREVIOUS_DEST=""
                fi
                # update PID to current process to avoid multiple concurrent resumes
                fn_run_cmd "echo $MYPID > $INPROGRESS_FILE"
        fi
fi


# Run in a loop to handle the "No space left on device" logic.
while : ; do

        # -----------------------------------------------------------------------------
        # Check if we are doing an incremental backup (if previous backup exists).
        # -----------------------------------------------------------------------------

        LINK_DEST_OPTION=""
        if [ -z "$PREVIOUS_DEST" ]; then
                fn_log_info "No previous backup - creating new one."
        else
                # If the path is relative, it needs to be relative to the destination. To keep
                # it simple, just use an absolute path. See http://serverfault.com/a/210058/118679
                PREVIOUS_DEST="$(fn_get_absolute_path "$PREVIOUS_DEST")"
                fn_log_info "Previous backup found - doing incremental backup from $SSH_DEST_FOLDER_PREFIX$PREVIOUS_DEST"
                LINK_DEST_OPTION="--link-dest='$PREVIOUS_DEST'"
        fi

        # -----------------------------------------------------------------------------
        # Create destination folder if it doesn't already exists
        # -----------------------------------------------------------------------------

        if [ -z "$(fn_find "$DEST -type d" 2>/dev/null)" ]; then
                fn_log_info "Creating destination $SSH_DEST_FOLDER_PREFIX$DEST"
                fn_mkdir "$DEST"
        fi

        # -----------------------------------------------------------------------------
        # Purge certain old backups before beginning new backup.
        # -----------------------------------------------------------------------------

        if [ -n "$PREVIOUS_DEST" ]; then
                # regardless of expiry strategy keep backup used for --link-dest
                fn_expire_backups "$PREVIOUS_DEST"
        else
                # keep latest backup
                fn_expire_backups "$DEST"
        fi

        # -----------------------------------------------------------------------------
        # Purge certain old backups before beginning new backup.
        # -----------------------------------------------------------------------------

        # Llamar a la función de pruning basado en cantidad antes de iniciar el backup.
        fn_prune_backups



        if [ -n "$PREVIOUS_DEST" ]; then
                fn_expire_backups "$PREVIOUS_DEST"
        else
                fn_expire_backups "$DEST"
        fi

        # -----------------------------------------------------------------------------
        # Start backup
        # -----------------------------------------------------------------------------

        LOG_FILE="$LOG_DIR/$(date +"%Y-%m-%d-%H%M%S").log"

        fn_log_info "Starting backup..."
        fn_log_info "From: $SSH_SRC_FOLDER_PREFIX$SRC_FOLDER/"
        fn_log_info "To:   $SSH_DEST_FOLDER_PREFIX$DEST/"

        # ---------------- Preflight diagnostics (common pitfalls) ----------------
        # 1) --one-file-system prevents crossing mount points like /home when backing up from '/'
        if echo " $RSYNC_FLAGS " | grep -q " --one-file-system"; then
            # Only relevant when source is root '/'
            if [ "$SSH_SRC_FOLDER_PREFIX$SRC_FOLDER" = "$SSH_SRC_FOLDER_PREFIX/" ] || [ "$SRC_FOLDER" = "/" ]; then
                # Check if / and /home are on different filesystems on the SOURCE side
                # Use POSIX df -P to get the device column reliably
                ROOT_DEV=$(fn_run_cmd_src "df -P / | tail -1 | awk '{print \$1}'" 2>/dev/null)
                HOME_DEV=$(fn_run_cmd_src "df -P /home 2>/dev/null | tail -1 | awk '{print \$1}'" 2>/dev/null)
                if [ -n "$ROOT_DEV" ] && [ -n "$HOME_DEV" ] && [ "$ROOT_DEV" != "$HOME_DEV" ]; then
                    fn_log_warn "Detected separate filesystem for /home ($HOME_DEV vs $ROOT_DEV) while using --one-file-system. /home will NOT be backed up. Consider using --rsync-set-flags to remove --one-file-system. See README Troubleshooting."
                fi
            fi
        fi

        # 2) Warn when not running as root on source and attempting to include /root
        SRC_UID=$(fn_run_cmd_src "id -u" 2>/dev/null)
        if [ -n "$SRC_UID" ] && [ "$SRC_UID" != "0" ]; then
            # If backing up from '/'
            if [ "$SSH_SRC_FOLDER_PREFIX$SRC_FOLDER" = "$SSH_SRC_FOLDER_PREFIX/" ] || [ "$SRC_FOLDER" = "/" ]; then
                if fn_run_cmd_src "test -d /root"; then
                    fn_log_warn "Source user UID=$SRC_UID is not root. Files under /root and other root-only paths may not be readable and thus not backed up. Run as root or adjust which paths you back up."
                fi
            fi
        fi

        # 3) Informative: does /backups_mysql exist on source?
        if [ "$SSH_SRC_FOLDER_PREFIX$SRC_FOLDER" = "$SSH_SRC_FOLDER_PREFIX/" ] || [ "$SRC_FOLDER" = "/" ]; then
            if ! fn_run_cmd_src "test -d /backups_mysql"; then
                fn_log_info "/backups_mysql not found on source. If you expect it, verify the path or mounts."
            fi
        fi

        CMD="rsync"
        if [ -n "$SSH_CMD" ]; then
                RSYNC_FLAGS="$RSYNC_FLAGS --compress"
                if [ -n "$ID_RSA" ] ; then
                        CMD="$CMD  -e 'ssh -p $SSH_PORT -i $ID_RSA -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"
                else
                        CMD="$CMD  -e 'ssh -p $SSH_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'"
                fi
        fi
        CMD="$CMD $RSYNC_FLAGS"
        CMD="$CMD --log-file '$LOG_FILE'"
        if [ -n "$EXCLUSION_FILE" ]; then
                # If the exclusions file uses rsync filter rules (+/-), switch to --filter merge
                if [ -f "$EXCLUSION_FILE" ] && grep -Eq '^[[:space:]]*[+\-][[:space:]]' "$EXCLUSION_FILE"; then
                        # Use filter-merge to support include/exclude rules in one file
                        CMD="$CMD --filter 'merge $EXCLUSION_FILE'"
                else
                        # Fallback to classic exclude-from (exclude-only patterns)
                        CMD="$CMD --exclude-from '$EXCLUSION_FILE'"
                fi
        fi
        CMD="$CMD $LINK_DEST_OPTION"
        CMD="$CMD '$SSH_SRC_FOLDER_PREFIX$SRC_FOLDER/' '$SSH_DEST_FOLDER_PREFIX$DEST/'"

        fn_log_info "Running command:"
        fn_log_info "$CMD"

        fn_run_cmd "echo $MYPID > $INPROGRESS_FILE"
        eval $CMD

        # -----------------------------------------------------------------------------
        # Check if we ran out of space
        # -----------------------------------------------------------------------------

        NO_SPACE_LEFT="$(grep "No space left on device (28)\|Result too large (34)" "$LOG_FILE")"

        if [ -n "$NO_SPACE_LEFT" ]; then

                if [[ $AUTO_EXPIRE == "0" ]]; then
                        fn_log_error "No space left on device, and automatic purging of old backups is disabled."
                        exit 1
                fi

                fn_log_warn "No space left on device - removing oldest backup and resuming."

                if [[ "$(fn_find_backups | wc -l)" -lt "2" ]]; then
                        fn_log_error "No space left on device, and no old backup to delete."
                        exit 1
                fi

                fn_expire_backup "$(fn_find_backups | tail -n 1)"

                # Resume backup
                continue
        fi

        # -----------------------------------------------------------------------------
        # Check whether rsync reported any errors
        # -----------------------------------------------------------------------------

        EXIT_CODE="1"
        if [ -n "$(grep "rsync error:" "$LOG_FILE")" ]; then
                fn_log_error "Rsync reported an error. Run this command for more details: grep -E 'rsync:|rsync error:' '$LOG_FILE'"
        elif [ -n "$(grep "rsync:" "$LOG_FILE")" ]; then
                fn_log_warn "Rsync reported a warning. Run this command for more details: grep -E 'rsync:|rsync error:' '$LOG_FILE'"
        else
                fn_log_info "Backup completed without errors."
                if [[ $AUTO_DELETE_LOG == "1" ]]; then
                        rm -f "$LOG_FILE"
                fi
                EXIT_CODE="0"
        fi

        # -----------------------------------------------------------------------------
        # Add symlink to last backup
        # -----------------------------------------------------------------------------
        if [ "$EXIT_CODE" = 0 ]; then
                # Create the latest symlink only when rsync succeeded
                fn_rm_file "$DEST_FOLDER/latest"
                fn_ln "$(basename "$DEST")" "$DEST_FOLDER/latest"

                # Remove .inprogress file only when rsync succeeded
                fn_rm_file "$INPROGRESS_FILE"

                ultimo_directorio="$DEST_FOLDER/$(basename "$DEST")"
                fn_log_info "Check permissions on $ultimo_directorio"
                fn_fix_permissions "$ultimo_directorio"
        fi

        exit $EXIT_CODE
done
