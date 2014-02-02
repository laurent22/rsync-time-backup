# Rsync time backup

Time Machine style backup with rsync. Should work on Linux, OS X and Windows with Cygwin.

# Installation

	git clone https://github.com/laurent22/rsync-time-backup

# Usage

	rsync_tmbackup.sh <source> <destination> [excluded-pattern-path]

## Examples
	
* Backup the home folder to backup_drive
	
		rsync_tmbackup.sh /home /mnt/backup_drive  

* Backup with exclusion list:
	
		rsync_tmbackup.sh /home /mnt/backup_drive excluded_patterns.txt
	
## Exclude file

An optional exclude file can be provided as a third parameter. It should be compatible with the `--exclude-from` parameter of rsync. See [this tutorial] (https://sites.google.com/site/rsync2u/home/rsync-tutorial/the-exclude-from-option) for more information.

# Features

* Each backup is on its own folder named after the current timestamp. Files can be copied and restored directly, without any intermediate tool.

* Files that haven't changed from one backup to the next are hard-linked to the previous backup so take very little extra space.

* Safety check - the backup will only happen if the destination has explicitly been marked as a backup destination.

* Resume feature - if a backup has failed or was interrupted, the tool will resume from there on the next backup.

* Exclude file - support for pattern-based exclusion via the `--exclude-from` rsync parameter.

* Automatically purge old backups - within 24 hours, all backups are kept. Within one month, the most recent backup for each day is kept. For all previous backups, the most recent of each month is kept.

* "latest" symlink that points to the latest successful backup.

* The application is just one bash script that can be easily edited.

# TODO

* Check source and destination file-system. If one of them is FAT, use the --modify-window rsync parameter (see `man rsync`) with a value of 1 or 2.

* Minor changes (see TODO comments in the source).

* Backup to remote drive?

# LICENSE

[MIT](http://opensource.org/licenses/MIT)

[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/laurent22/rsync-time-backup/trend.png)](https://bitdeli.com/free "Bitdeli Badge")
