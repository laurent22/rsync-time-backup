<?php

require_once dirname(__FILE__) . '/BaseTestCase.php';

class BasicTest extends BaseTestCase {

	private function makeDir($dir) {
		if (!file_exists($dir)) {
			$ok = @mkdir($dir, 0777, true);
			if (!$ok) throw new Exception('Could not create source directory: ' . $dir);
		}
		return $dir;
	}

	private function sourceDir() {
		return $this->makeDir(dirname(__FILE__) . '/data/source');
	}

	private function destDir() {
		return $this->makeDir(dirname(__FILE__) . '/data/dest');
	}

	private function scriptPath() {
		return dirname(dirname(__FILE__)) . '/rsync_tmbackup.sh';
	}

	private function execScript($args) {
		$cmd = $this->scriptPath() . ' ' . implode(' ', $args);
		exec($cmd, $output, $errorCode);
		return array(
			'output' => $output,
			'errorCode' => $errorCode,
		);
	}

	public function testFilesAreCopied() {
		//$this->execScript(
	}

}