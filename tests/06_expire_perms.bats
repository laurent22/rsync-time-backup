#!/usr/bin/env bats
#
# Regression tests for expire phase when snapshots contain files/dirs
# without owner write bit (e.g. ISPConfig .php-fcgi-starter at mode 0500,
# web1/ directories at 0550). Before the fix, `rm -rf` in fn_expire_backup
# would fail with "Permission denied" on these snapshots.
#

load 'test_helper'

setup() {
    setup_test_environment
    create_sample_files "$TEST_SOURCE" 2
}

teardown() {
    # Restore perms so teardown's rm -rf works even if a test failed mid-way
    if [ -n "$TEST_TEMP_DIR" ] && [ -d "$TEST_TEMP_DIR" ]; then
        chmod -R u+rwX "$TEST_TEMP_DIR" 2>/dev/null || true
    fi
    teardown_test_environment
}

@test "expire removes snapshot containing 0500 file (ISPConfig .php-fcgi-starter case)" {
    # Backup 1 (will become the one to expire)
    run "$SCRIPT_PATH" -m 1 "$TEST_SOURCE" "$TEST_DEST"
    assert_success

    local oldest
    oldest=$(find "$TEST_DEST" -maxdepth 1 -type d -name "????-??-??-??????" | head -1)
    [ -n "$oldest" ]

    # Inject the problematic perms inside the first snapshot
    mkdir -p "$oldest/var/www/php-fcgi-scripts/web1"
    echo '#!/bin/bash' > "$oldest/var/www/php-fcgi-scripts/web1/.php-fcgi-starter"
    chmod 0500 "$oldest/var/www/php-fcgi-scripts/web1/.php-fcgi-starter"
    chmod 0550 "$oldest/var/www/php-fcgi-scripts/web1"

    sleep 1

    # Backup 2 with -m 1 must expire backup 1 — this is where the bug fires
    echo "trigger" >> "$TEST_SOURCE/file_1.txt"
    run "$SCRIPT_PATH" -m 1 "$TEST_SOURCE" "$TEST_DEST"
    assert_success

    assert_dir_not_exists "$oldest"

    local count
    count=$(count_backups "$TEST_DEST")
    [ "$count" -eq 1 ]
}

@test "expire removes snapshot with 0400 file and 0700 parent dir" {
    run "$SCRIPT_PATH" -m 1 "$TEST_SOURCE" "$TEST_DEST"
    assert_success

    local oldest
    oldest=$(find "$TEST_DEST" -maxdepth 1 -type d -name "????-??-??-??????" | head -1)

    mkdir -p "$oldest/etc/ssl/private"
    echo 'fake-key' > "$oldest/etc/ssl/private/server.key"
    chmod 0400 "$oldest/etc/ssl/private/server.key"
    chmod 0700 "$oldest/etc/ssl/private"

    sleep 1

    echo "trigger" >> "$TEST_SOURCE/file_1.txt"
    run "$SCRIPT_PATH" -m 1 "$TEST_SOURCE" "$TEST_DEST"
    assert_success

    assert_dir_not_exists "$oldest"
}
