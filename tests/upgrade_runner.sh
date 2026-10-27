#!/usr/bin/env bash
set -Eeuo pipefail
source "$UPGRADE_PATH"

require_root() { :; }
detect_arch() { asset_name=V2bX-linux-64.zip; }
detect_service() { service_kind=mock; }
sleep() { :; }
service_is_active() { [[ $(cat "$TEST_ROOT/service-state") == 1 ]]; }
service_stop() { printf 'stop\n' >> "$TEST_ROOT/service-actions"; printf '0\n' > "$TEST_ROOT/service-state"; }
service_start() {
    printf 'start\n' >> "$TEST_ROOT/service-actions"
    if [[ $TEST_CASE == startup-failure ]] && grep -q test-new "$V2BX_INSTALL_DIR/V2bX"; then return 1; fi
    printf '1\n' > "$TEST_ROOT/service-state"
}
download_file() {
    case "$1" in
        */releases/latest) printf '{"tag_name":"v-test"}\n' > "$2" ;;
        *.zip.sha256)
            [[ $TEST_CASE != download-failure ]] || return 22
            if [[ $TEST_CASE == checksum-failure ]]; then printf '%064d  archive.zip\n' 0 > "$2"
            else sha256sum "$FIXTURE_DIR/archive.zip" > "$2"; fi ;;
        *.zip) cp "$FIXTURE_DIR/archive.zip" "$2" ;;
        */V2bX.sh) cp "$FIXTURE_DIR/manager.sh" "$2" ;;
        *) printf 'Unexpected download: %s\n' "$1" >&2; return 1 ;;
    esac
}
main
