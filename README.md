# Rsync time backup

This script offers Time Machine-style backup using rsync. It creates incremental backups of files and directories to the destination of your choice. The backups are structured in a way that makes it easy to recover any file at any point in time.

It should work on Linux, OS X and Windows with Cygwin. The main advantage over Time Machine is the flexibility as it can backup from/to any filesystem and works on any platform.

On OS X, it has a few disadvantages compared to Time Machine - in particular it doesn't auto-start when the backup drive is plugged (though it can be achieved using a launch agent), it requires some knowledge of the command line, and no specific GUI is provided to restore files. Instead files can be restored by using Finder, or the command line.

##NOTES:
1. I have forked this from https://github.com/laurent22/rsync-time-backup.git

# Installation

	git clone https://github.com/JohnKaul/rsync-time-backup.git

# Usage

	sudo rsync_tmbackup.sh -s <source> -d <destination> -e <excluded-pattern-file>

## Argument Flags
The arguments can be given in any order 
* -s    The source location.
* -d    The desination location
* -x    Designates a dry-run should be made (no actual folders created, backup made, or links updated).

## Examples

* Backup the `home` folder to `backup_drive`

		sudo rsync_tmbackup.sh -s /home -d /mnt/backup_drive

* Same as above but with exclusion list:

		sudo rsync_tmbackup.sh -s /home -d /mnt/backup_drive -e excluded_patterns.txt

* Dry-run of above example:

		sudo rsync_tmbackup.sh -s /home -d /mnt/backup_drive -e excluded_patterns.txt -x

## Exclude file

An optional exclude file can be provided as a third parameter. It should be compatible with the `--exclude-from` parameter of rsync. See [this tutorial] (https://sites.google.com/site/rsync2u/home/rsync-tutorial/the-exclude-from-option) for more information.

A sample exclude file has also been added to this project for you to use in your backups. Please, read through this sample file and remove/add the entries you wish. A section header entitled `local stuff` has purposely been added the bottom of this `sample-exclude-file` so that you can use a simple `echo <ADDITION> >> sample-exclude-file` command from the command line. 

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

* Check source and destination file-system. If one of them is FAT, use the --modify-window rsync parameter (see `man rsync`) with a value of 1 or 2.

* Minor changes (see TODO comments in the source).

# CHANGELOG

* Added root only operation.

* Added the use of `getopt' so argument flags can be used.

* Added the ability to handle a default exclustion list found in a `.sync\IgnoreList` in the source directory.

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
