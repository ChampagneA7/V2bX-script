#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$test_dir/../upgrade.sh"
test_tmp_root=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
work_dir=$(mktemp -d "$test_tmp_root/v2bx-readiness-test.XXXXXXXX")
trap '[[ $work_dir == "$test_tmp_root"/v2bx-readiness-test.* && -d $work_dir ]] && rm -rf -- "$work_dir"' EXIT
V2BX_INSTALL_DIR="$work_dir"
service_pid() { printf '%s\n' "$test_pid"; }
cat > "$work_dir/V2bX" <<'BIN'
#!/usr/bin/env bash
case "$TEST_READY_MODE" in
    ready) printf 'V2bX nodes ready\n' ;;
    unknown-command) printf 'Unknown command check-ready\n' ;;
    pending) exit 1 ;;
esac
BIN
chmod 755 "$work_dir/V2bX"
test_pid=1234
export TEST_READY_MODE=ready
service_is_ready || { echo 'FAIL: initialized process was not ready'; exit 1; }
export TEST_READY_MODE=unknown-command
if service_is_ready; then echo 'FAIL: exit-zero unknown command was treated as ready'; exit 1; fi
export TEST_READY_MODE=pending
if service_is_ready; then echo 'FAIL: pending process was treated as ready'; exit 1; fi
test_pid=0
export TEST_READY_MODE=ready
if service_is_ready; then echo 'FAIL: invalid service PID was accepted'; exit 1; fi
printf 'PASS: readiness protocol, invalid PID and old-command rejection\n'
