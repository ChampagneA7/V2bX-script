#!/usr/bin/env bash
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_tmp_root=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
work_dir=$(mktemp -d "$test_tmp_root/v2bx-install-guard.XXXXXXXX")
trap '[[ $work_dir == "$test_tmp_root"/v2bx-install-guard.* && -d $work_dir ]] && rm -rf -- "$work_dir"' EXIT
cat > "$work_dir/runner.sh" <<'RUNNER'
source "$INSTALL_SCRIPT"
require_install_root() { :; }
# A broken guard must never reach real package management, service or filesystem operations.
install_fresh() { printf 'unexpected-fresh-install\n' > "$CASE_DIR/fresh"; return 97; }
curl() {
    local target=''
    while [[ $# -gt 0 ]]; do
        if [[ $1 == -o ]]; then target=$2; shift 2; else shift; fi
    done
    printf '#!/usr/bin/env bash\nprintf "migration-selected\\n" > "$CASE_DIR/migrated"\nexit 23\n' > "$target"
}
install_main
RUNNER
for scenario in executable non-executable config-only install-directory-only empty-install; do
    case_dir="$work_dir/$scenario"
    mkdir -p "$case_dir"
    if [[ $scenario != config-only && $scenario != empty-install ]]; then mkdir -p "$case_dir/install"; fi
    if [[ $scenario == executable || $scenario == non-executable ]]; then
        printf 'old-program\n' > "$case_dir/install/V2bX"
        chmod 644 "$case_dir/install/V2bX"
        [[ $scenario != executable ]] || chmod 755 "$case_dir/install/V2bX"
    fi
    if [[ $scenario == config-only ]]; then
        mkdir "$case_dir/config"
        printf '{"ApiKey":"do-not-change"}\n' > "$case_dir/config/config.json"
    fi
    set +e
    CASE_DIR="$case_dir" INSTALL_SCRIPT="$test_dir/../install.sh" \
        V2BX_INSTALL_DIR="$case_dir/install" V2BX_CONFIG_DIR="$case_dir/config" \
        bash "$work_dir/runner.sh"
    result=$?
    set -e
    if [[ $scenario == empty-install ]]; then
        [[ $result -eq 97 && -f $case_dir/fresh && ! -f $case_dir/migrated ]]
    else
        [[ $result -eq 23 && -f $case_dir/migrated && ! -f $case_dir/fresh ]]
    fi
    if [[ $scenario == non-executable || $scenario == executable ]]; then
        [[ $(cat "$case_dir/install/V2bX") == old-program ]]
    fi
    if [[ $scenario == config-only ]]; then
        [[ $(cat "$case_dir/config/config.json") == '{"ApiKey":"do-not-change"}' ]]
    fi
    printf 'PASS: install guard %s\n' "$scenario"
done
