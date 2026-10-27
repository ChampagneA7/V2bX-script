#!/usr/bin/env bash
set -Eeuo pipefail
source "$UPGRADE_PATH"

require_root() { :; }
detect_arch() { asset_name=V2bX-linux-64.zip; }
detect_service() { service_kind=mock; }
sleep() { :; }
service_is_active() {
    if [[ $TEST_CASE == rollback-stop-failure && -f $TEST_ROOT/new-started && ! -f $TEST_ROOT/health-failed ]]; then
        touch "$TEST_ROOT/health-failed"
        return 1
    fi
    [[ $(cat "$TEST_ROOT/service-state") == 1 ]]
}
service_is_ready() {
    if [[ $TEST_CASE == readiness-timeout ]]; then return 1; fi
    if [[ $TEST_CASE == readiness-lost && -f $TEST_ROOT/ready-once ]]; then return 1; fi
    touch "$TEST_ROOT/ready-once"
    return 0
}
service_stop() {
    printf 'stop\n' >> "$TEST_ROOT/service-actions"
    if [[ $TEST_CASE == stop-failure || ( $TEST_CASE == rollback-stop-failure && -f $TEST_ROOT/new-started ) ]]; then return 1; fi
    printf '0\n' > "$TEST_ROOT/service-state"
}
service_start() {
    printf 'start\n' >> "$TEST_ROOT/service-actions"
    if [[ $TEST_CASE == startup-failure ]] && grep -q test-new "$V2BX_INSTALL_DIR/V2bX"; then return 1; fi
    # systemctl start on an already-active service does not replace its running process.
    if [[ $(cat "$TEST_ROOT/service-state") == 1 ]]; then return 0; fi
    if grep -q test-new "$V2BX_INSTALL_DIR/V2bX"; then
        touch "$TEST_ROOT/new-started"
        printf 'new\n' > "$TEST_ROOT/running-version"
    else
        printf 'old\n' > "$TEST_ROOT/running-version"
    fi
    printf '1\n' > "$TEST_ROOT/service-state"
}
mv() {
    if [[ $TEST_CASE == manager-replacement-failure && ${@: -1} == "$V2BX_MANAGER_PATH" ]] && grep -q test-new "$V2BX_INSTALL_DIR/V2bX"; then return 1; fi
    command mv "$@"
}
archive_fixture="$FIXTURE_DIR/archive.zip"
if [[ $TEST_CASE == legacy-package ]]; then archive_fixture="$FIXTURE_DIR/legacy.zip"; fi
if [[ $TEST_CASE == bad-manager ]]; then archive_fixture="$FIXTURE_DIR/bad-manager.zip"; fi
download_file() {
    case "$1" in
        */releases/latest) printf '{"tag_name":"v-test"}\n' > "$2" ;;
        *.zip.sha256)
            [[ $TEST_CASE != download-failure ]] || return 22
            if [[ $TEST_CASE == checksum-failure ]]; then printf '%064d  archive.zip\n' 0 > "$2"
            else sha256sum "$archive_fixture" > "$2"; fi ;;
        *.zip) cp "$archive_fixture" "$2" ;;
        *) printf 'Unexpected download: %s\n' "$1" >&2; return 1 ;;
    esac
}
main
