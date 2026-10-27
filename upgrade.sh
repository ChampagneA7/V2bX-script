#!/usr/bin/env bash
# Migrate an existing wyx2685 installation, or update an existing ChampagneA7 installation.
# Configuration, certificates, routing files, geo databases and service definitions are never replaced.
set -Eeuo pipefail

V2BX_INSTALL_DIR=${V2BX_INSTALL_DIR:-/usr/local/V2bX}
V2BX_CONFIG_DIR=${V2BX_CONFIG_DIR:-/etc/V2bX}
V2BX_MANAGER_PATH=${V2BX_MANAGER_PATH:-/usr/bin/V2bX}
V2BX_REPO=ChampagneA7/V2bX
V2BX_READY_TIMEOUT=${V2BX_READY_TIMEOUT:-180}
stage_dir=''
backup_dir=''
lock_dir=''
upgrade_started=0
files_may_have_changed=0
was_active=0
temporary_files=()

die() { printf '错误：%s\n' "$*" >&2; exit 1; }
require_root() { [[ $EUID -eq 0 ]] || die '请使用 root 用户执行升级。'; }

download_file() {
    curl --fail --location --silent --show-error --retry 3 \
        --connect-timeout 15 --max-time 180 --output "$2" "$1"
}

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) asset_name=V2bX-linux-64.zip ;;
        aarch64|arm64) asset_name=V2bX-linux-arm64-v8a.zip ;;
        s390x) asset_name=V2bX-linux-s390x.zip ;;
        *) die '当前升级包支持 x86_64、arm64 和 s390x；未修改现有安装。' ;;
    esac
}

detect_service() {
    if command -v systemctl >/dev/null 2>&1 && \
        [[ $(systemctl show --property=LoadState --value V2bX.service 2>/dev/null) == loaded ]]; then
        service_kind=systemd
    elif command -v rc-service >/dev/null 2>&1 && [[ -f /etc/init.d/V2bX ]]; then
        service_kind=openrc
    else
        die '未检测到现有 V2bX systemd/OpenRC 服务；请勿用于 Docker 安装。'
    fi
}

service_is_active() {
    if [[ $service_kind == systemd ]]; then
        systemctl is-active --quiet V2bX.service
    else
        rc-service V2bX status >/dev/null 2>&1
    fi
}

service_stop() {
    if [[ $service_kind == systemd ]]; then systemctl stop V2bX.service
    else rc-service V2bX stop; fi
}

service_start() {
    if [[ $service_kind == systemd ]]; then systemctl start V2bX.service
    else rc-service V2bX start; fi
}

service_pid() {
    if [[ $service_kind == systemd ]]; then
        systemctl show --property=MainPID --value V2bX.service
    else
        cat /run/V2bX.pid
    fi
}

service_is_ready() {
    local pid status check_timeout=${1:-5}
    pid=$(service_pid) || return 1
    [[ $pid =~ ^[1-9][0-9]*$ ]] || return 1
    status=$(timeout "$check_timeout" "$V2BX_INSTALL_DIR/V2bX" check-ready "$pid" 2>/dev/null) || return 1
    [[ $status == 'V2bX nodes ready' ]]
}

atomic_install() {
    local source_file=$1 target_file=$2 pending_file
    pending_file=$(mktemp "${target_file}.upgrade.XXXXXXXX") || return 1
    temporary_files+=("$pending_file")
    cp -- "$source_file" "$pending_file" || return 1
    chmod 755 "$pending_file" || return 1
    mv -f -- "$pending_file" "$target_file" || return 1
}

restore_previous() {
    printf '\n升级失败，正在恢复旧程序和管理脚本……\n' >&2
    if [[ $files_may_have_changed -eq 0 ]]; then
        if [[ $was_active -eq 1 ]] && ! service_is_active; then
            service_start || return 1
            service_is_active || return 1
        fi
        printf '原程序尚未替换，已保留升级前服务状态。\n' >&2
        return 0
    fi
    if ! service_stop >/dev/null 2>&1; then
        if service_is_active; then
            printf '无法停止新版进程，不能确认回滚成功；保留备份供人工恢复。\n' >&2
            return 1
        fi
    fi
    if service_is_active; then return 1; fi
    atomic_install "$backup_dir/V2bX" "$V2BX_INSTALL_DIR/V2bX" || return 1
    atomic_install "$backup_dir/V2bX.sh" "$V2BX_MANAGER_PATH" || return 1
    if [[ $was_active -eq 1 ]]; then
        service_start || return 1
        service_is_active || return 1
    fi
    printf '已恢复升级前版本；配置未改动。备份：%s\n' "$backup_dir" >&2
}

finish_upgrade() {
    local result=$?
    trap - EXIT INT TERM
    set +e
    if [[ $upgrade_started -eq 1 ]]; then
        if ! restore_previous; then
            printf '自动恢复未成功，请检查服务日志。原程序备份：%s\n' "$backup_dir" >&2
        fi
        [[ $result -ne 0 ]] || result=1
    fi
    local pending_file
    for pending_file in "${temporary_files[@]}"; do rm -f -- "$pending_file"; done
    # Only remove the exact mktemp staging directory belonging to this upgrade.
    if [[ -n $stage_dir && $stage_dir == "$V2BX_INSTALL_DIR"/.v2bx-upgrade.* ]]; then
        rm -rf -- "$stage_dir"
    fi
    [[ -z $lock_dir ]] || rmdir -- "$lock_dir" 2>/dev/null
    exit "$result"
}

main() {
    require_root
    [[ $# -le 1 ]] || die '用法：bash upgrade.sh [版本号]'
    local requested_version=${1:-latest} command_name expected_digest actual_digest release_url
    [[ -n $requested_version ]] || requested_version=latest
    [[ $V2BX_READY_TIMEOUT =~ ^[1-9][0-9]{0,3}$ && $V2BX_READY_TIMEOUT -le 3600 ]] || die 'V2BX_READY_TIMEOUT 必须是 1 到 3600 秒。'
    for command_name in curl unzip sha256sum tar mktemp timeout bash; do
        command -v "$command_name" >/dev/null 2>&1 || die "缺少依赖：$command_name；请安装后重试。"
    done
    [[ -d $V2BX_INSTALL_DIR && -x $V2BX_INSTALL_DIR/V2bX ]] || die '未找到现有 V2bX 程序，请先安装。'
    [[ ! -L $V2BX_INSTALL_DIR/V2bX ]] || die '程序路径是符号链接，请先核对实际安装位置。'
    [[ -d $V2BX_CONFIG_DIR ]] || die '未找到现有配置目录；未修改安装。'
    [[ -f $V2BX_MANAGER_PATH ]] || die '未找到原有 V2bX 管理脚本。'
    if [[ -L $V2BX_MANAGER_PATH ]]; then V2BX_MANAGER_PATH=$(readlink -f "$V2BX_MANAGER_PATH"); fi
    detect_arch
    detect_service
    umask 077
    lock_dir="$V2BX_INSTALL_DIR/.upgrade.lock"
    mkdir -- "$lock_dir" 2>/dev/null || { lock_dir=''; die '另一个升级正在运行，或有遗留的 .upgrade.lock；请核对后再试。'; }
    trap finish_upgrade EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    stage_dir=$(mktemp -d "$V2BX_INSTALL_DIR/.v2bx-upgrade.XXXXXXXX")

    if [[ $requested_version == latest ]]; then
        download_file "https://api.github.com/repos/$V2BX_REPO/releases/latest" "$stage_dir/release.json"
        requested_version=$(sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$stage_dir/release.json" | head -n 1)
    fi
    [[ $requested_version =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die '无法确定有效的 Release 版本；现有服务未停止。'
    release_url="https://github.com/$V2BX_REPO/releases/download/$requested_version"
    printf '准备升级到 %s/%s，下载并校验 %s……\n' "$V2BX_REPO" "$requested_version" "$asset_name"
    download_file "$release_url/$asset_name" "$stage_dir/$asset_name"
    download_file "$release_url/$asset_name.sha256" "$stage_dir/$asset_name.sha256"
    expected_digest=$(awk 'NR == 1 {print $1}' "$stage_dir/$asset_name.sha256")
    [[ $expected_digest =~ ^[a-fA-F0-9]{64}$ ]] || die 'Release 校验文件无效；现有服务未停止。'
    actual_digest=$(sha256sum "$stage_dir/$asset_name")
    actual_digest=${actual_digest%% *}
    [[ ${expected_digest,,} == "$actual_digest" ]] || die '程序包 SHA256 校验失败；现有服务未停止。'
    # Extract only the executable. Never extract example configuration over an existing installation.
    unzip -p "$stage_dir/$asset_name" V2bX > "$stage_dir/V2bX"
    chmod 755 "$stage_dir/V2bX"
    timeout 15 "$stage_dir/V2bX" version > "$stage_dir/version.txt"
    # Keep program and manager from the same reviewed, checksummed release.
    unzip -p "$stage_dir/$asset_name" V2bX.sh > "$stage_dir/V2bX.sh"
    [[ -s $stage_dir/V2bX.sh ]] || die '此 Release 未包含配套管理脚本；现有服务未停止。'
    bash -n "$stage_dir/V2bX.sh"

    mkdir -p -- "$V2BX_INSTALL_DIR/backups"
    backup_dir=$(mktemp -d "$V2BX_INSTALL_DIR/backups/$(date +%Y%m%d-%H%M%S).XXXXXXXX")
    cp -p -- "$V2BX_INSTALL_DIR/V2bX" "$backup_dir/V2bX"
    cp -p -- "$V2BX_MANAGER_PATH" "$backup_dir/V2bX.sh"
    tar -C "$V2BX_CONFIG_DIR" -cpf "$backup_dir/config.tar" .
    printf '%s\n' "$requested_version" > "$backup_dir/upgrade-target.txt"
    if service_is_active; then was_active=1; fi
    printf '%s\n' "$was_active" > "$backup_dir/service-was-active.txt"
    upgrade_started=1
    if [[ $was_active -eq 1 ]]; then service_stop; fi
    files_may_have_changed=1
    atomic_install "$stage_dir/V2bX" "$V2BX_INSTALL_DIR/V2bX"
    atomic_install "$stage_dir/V2bX.sh" "$V2BX_MANAGER_PATH"
    if [[ $was_active -eq 1 ]]; then
        service_start
        local ready=0 deadline remaining
        deadline=$((SECONDS + V2BX_READY_TIMEOUT))
        while (( SECONDS < deadline )); do
            service_is_active || die '新版服务在初始化期间退出。'
            remaining=$((deadline - SECONDS))
            if (( remaining > 5 )); then remaining=5; fi
            if service_is_ready "$remaining"; then ready=1; break; fi
            sleep 1
        done
        [[ $ready -eq 1 ]] || die '新版未在时限内完成节点初始化。'
        for _ in 1 2 3 4 5; do
            sleep 1
            service_is_active || die '新版服务未保持运行。'
            service_is_ready || die '新版节点未保持就绪状态。'
        done
    fi
    upgrade_started=0
    printf '\n升级完成。原配置、证书、路由、geo 数据和服务定义均未替换。\n'
    printf '备份目录：%s\n' "$backup_dir"
    cat "$stage_dir/version.txt"
    if [[ $was_active -eq 0 ]]; then printf '升级前服务已停止，目前继续保持停止状态。\n'; fi
    printf '以后升级：V2bX update\n指定版本：V2bX update %s\n' "$requested_version"
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then main "$@"; fi
