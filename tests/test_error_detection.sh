#!/bin/bash
#
# Tests for rsync error/warning detection patterns.
# Verifies that the log-file grep patterns in rsync_tmbackup.sh match
# both GNU rsync and openrsync (macOS Sequoia+) message formats.

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$SCRIPT_DIR/rsync_tmbackup.sh"

PASS=0
FAIL=0

assert_matches() {
	local description="$1"
	local pattern="$2"
	local input="$3"

	if echo "$input" | grep -E "$pattern" > /dev/null 2>&1; then
		PASS=$((PASS + 1))
	else
		echo "FAIL: $description"
		echo "  pattern: $pattern"
		echo "  input:   $input"
		FAIL=$((FAIL + 1))
	fi
}

assert_no_match() {
	local description="$1"
	local pattern="$2"
	local input="$3"

	if echo "$input" | grep -E "$pattern" > /dev/null 2>&1; then
		echo "FAIL: $description (unexpected match)"
		echo "  pattern: $pattern"
		echo "  input:   $input"
		FAIL=$((FAIL + 1))
	else
		PASS=$((PASS + 1))
	fi
}

# Extract the error and warning patterns from the script itself,
# so the tests break if the patterns are changed without updating tests.
ERROR_PATTERN=$(sed -n 's/.*grep -E "\(.*\)" "$LOG_FILE".*/\1/p' "$SCRIPT" | head -1)
WARNING_PATTERN=$(sed -n 's/.*grep -E "\(.*\)" "$LOG_FILE".*/\1/p' "$SCRIPT" | tail -1)

# If extraction failed, fall back to the known patterns.
if [ -z "$ERROR_PATTERN" ] || [ -z "$WARNING_PATTERN" ]; then
	echo "WARNING: Could not extract patterns from script, using hardcoded values"
	ERROR_PATTERN='rsync error:|rsync\([0-9]+\): error:'
	WARNING_PATTERN='rsync:|rsync\([0-9]+\): warning:'
fi

echo "Error pattern:   $ERROR_PATTERN"
echo "Warning pattern: $WARNING_PATTERN"
echo ""

# --- Error detection ---

assert_matches "GNU rsync error" \
	"$ERROR_PATTERN" \
	'rsync error: some files/attrs were not transferred (see previous errors) (code 23) at main.c(1819) [sender=3.2.7]'

assert_matches "openrsync error (mmap)" \
	"$ERROR_PATTERN" \
	'rsync(13347): error: /Users/user/Library/CloudStorage/Dropbox/videos/file.mov: mmap: Operation timed out'

assert_matches "openrsync error (permission denied)" \
	"$ERROR_PATTERN" \
	'rsync(78802): error: /path/to/file: open (2) in /Users/user: Permission denied'

assert_matches "openrsync error (single digit PID)" \
	"$ERROR_PATTERN" \
	'rsync(1): error: /path/to/file: some error'

assert_matches "openrsync error (large PID)" \
	"$ERROR_PATTERN" \
	'rsync(999999): error: /path/to/file: some error'

assert_no_match "normal transfer line should not match error pattern" \
	"$ERROR_PATTERN" \
	'>f+++++++ Dropbox/videos/something.mp4'

assert_no_match "stats line should not match error pattern" \
	"$ERROR_PATTERN" \
	'sent 3018k bytes  received 42 bytes  177M bytes/sec'

# --- Warning detection ---

assert_matches "GNU rsync warning" \
	"$WARNING_PATTERN" \
	'rsync: some warning message'

assert_matches "openrsync warning" \
	"$WARNING_PATTERN" \
	'rsync(13347): warning: /path/to/file: some warning'

assert_no_match "normal transfer line should not match warning pattern" \
	"$WARNING_PATTERN" \
	'>f+++++++ Dropbox/videos/something.mp4'

assert_no_match "stats line should not match warning pattern" \
	"$WARNING_PATTERN" \
	'sent 3018k bytes  received 42 bytes  177M bytes/sec'

# --- Error should not match as mere warning ---

assert_no_match "openrsync error should not match warning-only pattern" \
	'rsync\([0-9]+\): warning:' \
	'rsync(13347): error: /path/to/file: mmap: Operation timed out'

# --- Summary ---

echo ""
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
	echo "All $TOTAL tests passed."
	exit 0
else
	echo "$FAIL of $TOTAL tests failed."
	exit 1
fi
