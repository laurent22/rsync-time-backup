<?php

// This PHP script can be used to test the expiration strategy.
// It is going to populate a directory with fake backup sets (directories named Y-m-d-His) over several months.
// Then the backup script can be run on it to check what directories are going to be deleted.

// rm -rf ./tests/TestDest/201* && php ./tests/populate_dest.php && ./rsync_tmbackup.sh ./tests/TestSource/ ./tests/TestDest/

$baseDir = dirname(__FILE__);
$destDir = $baseDir . '/TestDest';

$backupsPerDay = 2;
$totalDays = 500;

$intervalBetweenBackups = null;
if ($backupsPerDay === 1) {
	$intervalBetweenBackups = 'PT1D';
} else if ($backupsPerDay === 2) {
	$intervalBetweenBackups = 'PT12H';
} else {
	throw new Exception('Not implemented');
}

$d = new DateTime();
$d->sub(new DateInterval('P' . $totalDays . 'D'));

for ($i = 0; $i < $backupsPerDay * $totalDays; $i++) {
	$d->add(new DateInterval($intervalBetweenBackups));
	mkdir($destDir . '/' . $d->format('Y-m-d-His'), 0777, true);
}