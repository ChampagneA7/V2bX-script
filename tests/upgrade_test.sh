#!/usr/bin/env bash
# Runs against temporary directories and fake services; never touches an installed V2bX.
set -Eeuo pipefail
test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_tmp_root=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
work_dir=$(mktemp -d "$test_tmp_root/v2bx-upgrade-tests.XXXXXXXX")
trap '[[ $work_dir == "$test_tmp_root"/v2bx-upgrade-tests.* && -d $work_dir ]] && rm -rf -- "$work_dir"' EXIT
fixture_dir="$work_dir/fixtures"
mkdir -p "$fixture_dir"
node "$test_dir/make_fixture.mjs" "$fixture_dir/archive.zip"
printf '#!/usr/bin/env bash\necho new-manager\n' > "$fixture_dir/manager.sh"
scenarios=(success stopped download-failure checksum-failure startup-failure concurrent-upgrade)
ln -s "$fixture_dir/manager.sh" "$work_dir/symlink-probe"
if [[ -L $work_dir/symlink-probe ]]; then
    scenarios+=(symlink-manager)
else
    printf 'SKIP: symlink-manager (this platform emulates symbolic links as copies)\n'
fi
trap 'if [[ ${allow_failure:-0} -eq 0 ]]; then printf "FAIL: %s at line %s\n" "${scenario:-setup}" "$LINENO" >&2; [[ ! -f ${case_dir:-}/output.log ]] || cat "$case_dir/output.log"; fi' ERR

for scenario in "${scenarios[@]}"; do
    case_dir="$work_dir/$scenario"
    mkdir -p "$case_dir/install" "$case_dir/config" "$case_dir/bin"
    printf '#!/usr/bin/env bash\necho V2bX test-old\n' > "$case_dir/install/V2bX"
    printf '#!/usr/bin/env bash\necho old-manager\n' > "$case_dir/bin/V2bX"
    chmod 755 "$case_dir/install/V2bX" "$case_dir/bin/V2bX"
    cp "$case_dir/install/V2bX" "$case_dir/old-binary"
    cp "$case_dir/bin/V2bX" "$case_dir/old-manager"
    if [[ $scenario == symlink-manager ]]; then
        mv "$case_dir/bin/V2bX" "$case_dir/bin/manager-target"
        ln -s manager-target "$case_dir/bin/V2bX"
    fi
    printf '{"ApiKey":"keep-this-secret","Core":"sing"}\n' > "$case_dir/config/config.json"
    printf '{"rules":["custom-route"]}\n' > "$case_dir/config/route.json"
    printf 'existing-private-key\n' > "$case_dir/config/cert.key"
    printf 'existing-geo-database\n' > "$case_dir/install/geoip.dat"
    printf '1\n' > "$case_dir/service-state"
    [[ $scenario != stopped ]] || printf '0\n' > "$case_dir/service-state"
    [[ $scenario != concurrent-upgrade ]] || mkdir "$case_dir/install/.upgrade.lock"
    fingerprint_before=$(find "$case_dir/config" -type f -exec sha256sum {} \;)
    allow_failure=1
    set +e
    TEST_ROOT="$case_dir" TEST_CASE="$scenario" FIXTURE_DIR="$fixture_dir" \
        V2BX_INSTALL_DIR="$case_dir/install" V2BX_CONFIG_DIR="$case_dir/config" \
        V2BX_MANAGER_PATH="$case_dir/bin/V2bX" UPGRADE_PATH="$test_dir/../upgrade.sh" \
        bash "$test_dir/upgrade_runner.sh" > "$case_dir/output.log" 2>&1
    result=$?
    set -e
    allow_failure=0
    fingerprint_after=$(find "$case_dir/config" -type f -exec sha256sum {} \;)
    [[ $fingerprint_before == "$fingerprint_after" ]] || { cat "$case_dir/output.log"; echo "FAIL: $scenario changed configuration"; exit 1; }
    [[ $(cat "$case_dir/install/geoip.dat") == existing-geo-database ]] || exit 1
    if [[ $scenario == success || $scenario == stopped || $scenario == symlink-manager ]]; then
        [[ $result -eq 0 ]] || { cat "$case_dir/output.log"; exit 1; }
        grep -q test-new "$case_dir/install/V2bX"
        cmp "$fixture_dir/manager.sh" "$case_dir/bin/V2bX"
        backup=$(find "$case_dir/install/backups" -name config.tar -print -quit)
        [[ -f $backup ]]
        cmp "$case_dir/old-binary" "${backup%/*}/V2bX"
        cmp "$case_dir/old-manager" "${backup%/*}/V2bX.sh"
    else
        [[ $result -ne 0 ]] || { cat "$case_dir/output.log"; echo "FAIL: $scenario unexpectedly succeeded"; exit 1; }
        cmp "$case_dir/old-binary" "$case_dir/install/V2bX"
        cmp "$case_dir/old-manager" "$case_dir/bin/V2bX"
    fi
    if [[ $scenario == stopped ]]; then
        [[ $(cat "$case_dir/service-state") == 0 && ! -f $case_dir/service-actions ]]
    else
        [[ $(cat "$case_dir/service-state") == 1 ]]
    fi
    if [[ $scenario == symlink-manager ]]; then [[ -L $case_dir/bin/V2bX ]]; fi
    if [[ $scenario == download-failure || $scenario == checksum-failure || $scenario == concurrent-upgrade ]]; then
        [[ ! -f $case_dir/service-actions ]] || { echo "FAIL: $scenario stopped the service"; exit 1; }
    fi
    printf 'PASS: %s (configuration, certificates and geo data unchanged)\n' "$scenario"
done
