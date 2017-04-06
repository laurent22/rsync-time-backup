# Rsync time backup

This script offers Time Machine-style backup using rsync. It creates incremental backups of files and directories to the destination of your choice. The backups are structured in a way that makes it easy to recover any file at any point in time.

It should work on Linux, OS X and Windows with Cygwin. The main advantage over Time Machine is the flexibility as it can backup from/to any filesystem and works on any platform. You can also backup, for example, to a Truecrypt drive without any problem.

On OS X, it has a few disadvantages compared to Time Machine - in particular it doesn't auto-start when the backup drive is plugged (though it can be achieved using a launch agent), it requires some knowledge of the command line, and no specific GUI is provided to restore files. Instead files can be restored by using any file explorer, including Finder, or the command line.

# Installation

	git clone https://github.com/laurent22/rsync-time-backup

# Usage

	rsync_tmbackup.sh <source> <destination> [excluded-pattern-path]

## Examples
	
* Backup the home folder to backup_drive
	
		rsync_tmbackup.sh /home /mnt/backup_drive  

* Backup with exclusion list:
	
		rsync_tmbackup.sh /home /mnt/backup_drive excluded_patterns.txt

* Backup to remote drive over SSH, on port 2222:

        rsync_tmbackup.sh -p 2222 /home user@example.com:/mnt/backup_drive

* To mimic Time Machine's behaviour, a cron script can be setup to backup at regular interval. For example, the following cron job checks if the drive "/mnt/backup" is currently connected and, if it is, starts the backup. It does this check every 1 hour.

        0 */1 * * * if [[ -d /mnt/backup ]]; then rsync_tmbackup.sh /home /mnt/backup; fi 
	
## Exclude file

An optional exclude file can be provided as a third parameter. It should be compatible with the `--exclude-from` parameter of rsync. See [this tutorial](https://sites.google.com/site/rsync2u/home/rsync-tutorial/the-exclude-from-option) for more information.

## Rsync options

To display the rsync options that are used for backup, run `./rsync_tmbackup.sh --rsync-get-flags`. It is also possible to add or remove options using the `--rsync-set-flags` option. For example, to exclude backing up permissions and groups:

	rsync_tmbackup --rsync-set-flags "--numeric-ids --links --hard-links --one-file-system --archive --no-perms --no-groups --itemize-changes" /src /dest

## Lock file

The use of a lock-file is recommended for larger backups. Flock(1) is an easy way to get lock files and can be installed with Homebrew. Please refer to its GitHub [page](https://github.com/discoteq/flock) for more details. To use flock with the script, see this example:

	flock -n /tmp/rsync.lock sh -c 'sh rsync_tmbackup.sh /home /mnt/backup_drive'

# Features

* Each backup is on its own folder named after the current timestamp. Files can be copied and restored directly, without any intermediate tool.

* Backup to remote destinations over SSH.

* Files that haven't changed from one backup to the next are hard-linked to the previous backup so take very little extra space.

* Safety check - the backup will only happen if the destination has explicitly been marked as a backup destination.

* Resume feature - if a backup has failed or was interrupted, the tool will resume from there on the next backup.

* Exclude file - support for pattern-based exclusion via the `--exclude-from` rsync parameter.

* Automatically purge old backups - within 24 hours, all backups are kept. Within one month, the most recent backup for each day is kept. For all previous backups, the most recent of each month is kept.

* "latest" symlink that points to the latest successful backup.

# TODO

* Check source and destination file-system (`df -T /dest`). If one of them is FAT, use the --modify-window rsync parameter (see `man rsync`) with a value of 1 or 2
* Add `--whole-file` arguments on Windows? See http://superuser.com/a/905415/73619

* Minor changes (see TODO comments in the source).

# LICENSE

The MIT License (MIT)

Copyright (c) 2013-2016 Laurent Cozic

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
