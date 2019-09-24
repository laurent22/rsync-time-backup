<?php 

$backupDirectory = './TestDest/';

chdir(__DIR__);

exec('rm -rf ./TestDest');

include 'populate_dest.php';

exec('../rsync_tmbackup.sh --strategy "1:1 30:x" ./TestSource/ ' . $backupDirectory, $output, $return);

if ($return !== 0) {
    echo 'Invalid return code';
    echo implode(PHP_EOL, $output);
    exit(1);
}

$backups = array_filter(
    scandir($backupDirectory),
    function ($file) use ($backupDirectory) {
        return is_dir($backupDirectory . $file) && !in_array($file, ['.', '..']);
    }
);

$expected = 33;
if (count($backups) !== $expected) {
    echo 'Given this strategy there should be ' . $expected . ' directories. But ' . count($backups) . ' directories found.';
    echo 'Found directories:';
    echo implode(
        PHP_EOL, 
        array_map(
            function ($directory) { return "- {$directory}"; },
            $backups
        )
    );

    exit(1);
}

echo 'All assertions succeeded';
exit(0);