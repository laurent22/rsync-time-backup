#!/bin/sh

# rm -rf ./tests/TestDestM/201* && sh ./tests/populate_dest_monthly.php && ./rsync_tmbackup.sh ./tests/TestSource/ ./tests/TestDestM/

cd "$(dirname "$0")" || exit 2
[ -d TestDestM ] || mkdir TestDestM
cd TestDestM || exit 3

mkdir \
	2016-01-31-000009 \
	2016-02-01-000009 \
	2016-02-28-000009 \
	2016-03-01-000009 \
	2016-04-01-000010 \
	2016-04-30-000009 \
	2016-05-01-000009 \
	2016-06-17-194507 \
	2016-06-18-194725 \
	2016-06-19-200316

