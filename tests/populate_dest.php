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
	$d2 = clone $d;
	$dummyRand = cos($i);
	$tolI = new DateInterval('PT' . intval(abs(1 - $dummyRand) * 3600 * 0.2) . 'S');
	if ($dummyRand < 0) {
		$tolI->invert = 1;
	}
	$d2->add($tolI);
	mkdir($destDir . '/' . $d2->format('Y-m-d-His'), 0777, true);
}
