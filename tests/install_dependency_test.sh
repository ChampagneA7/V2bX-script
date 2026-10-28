#!/usr/bin/env bash
set -Eeuo pipefail

test_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
test_tmp_root=$(cd -- "${TMPDIR:-/tmp}" && pwd -P)
work_dir=$(mktemp -d "$test_tmp_root/v2bx-install-dependencies.XXXXXXXX")
trap '[[ $work_dir == "$test_tmp_root"/v2bx-install-dependencies.* && -d $work_dir ]] && rm -rf -- "$work_dir"' EXIT

source "$test_dir/../install.sh"

empty_path="$work_dir/empty"
mkdir -p "$empty_path"
set +e
missing_output=$(PATH="$empty_path" verify_install_dependencies 2>&1)
missing_result=$?
set -e
[[ $missing_result -ne 0 ]]
for command_name in curl wget unzip tar socat; do
    grep -qx "$command_name" <<< "$missing_output"
done
printf 'PASS: install dependencies report every missing command\n'

stub_path="$work_dir/bin"
mkdir -p "$stub_path"
for command_name in curl wget unzip tar socat; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stub_path/$command_name"
    chmod 755 "$stub_path/$command_name"
done
PATH="$stub_path" verify_install_dependencies
printf 'PASS: install dependencies accept all required commands\n'
