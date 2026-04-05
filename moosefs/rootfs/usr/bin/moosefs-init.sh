#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: MooseFS
# Generate runtime configuration for the GUI, proxy, NFS, and mount services.
# ==============================================================================

set -euo pipefail

is_true() {
    [[ "${1}" == "true" ]]
}

to_mfsgui_log_level() {
    case "${1}" in
        trace|debug)
            echo "DEBUG"
            ;;
        info)
            echo "INFO"
            ;;
        notice)
            echo "NOTICE"
            ;;
        warning)
            echo "WARNING"
            ;;
        error|fatal)
            echo "ERROR"
            ;;
        *)
            echo "INFO"
            ;;
    esac
}

write_mount_config() {
    local master_host="${1}"
    local master_port="${2}"
    local master_subfolder="${3}"
    local delayed_init="${4}"
    local password="${5}"

    cat <<EOF > /etc/mfs/mfsmount.cfg
mfsmaster=${master_host}
mfsport=${master_port}
mfssubfolder=${master_subfolder}
allow_other
EOF

    if is_true "${delayed_init}"; then
        echo "mfsdelayedinit" >> /etc/mfs/mfsmount.cfg
    fi

    if [[ -n "${password}" ]]; then
        printf '%s\n' "${password}" > /run/moosefs/master_password
        chmod 0600 /run/moosefs/master_password
        echo "mfspassfile=/run/moosefs/master_password" >> /etc/mfs/mfsmount.cfg
    else
        rm -f /run/moosefs/master_password
    fi
}

write_nfs_exports() {
    local mount_point="${1}"

    cat <<EOF > /etc/exports
${mount_point} *(rw,fsid=0,no_subtree_check,no_root_squash,sync,insecure)
EOF
}

find_gui_requests_file() {
    find /usr/share -type f -name 'requests.cfg' -print -quit 2>/dev/null || true
}

find_gui_root_dir() {
    local requests_file

    requests_file="$(find_gui_requests_file)"
    if [[ -z "${requests_file}" ]]; then
        return
    fi

    dirname "${requests_file}"
}

write_gui_config() {
    local mfsgui_log_level="${1}"
    local gui_root_dir="${2}"
    local gui_requests_file="${3}"

    cat <<EOF > /etc/mfs/mfsgui.cfg
WORKING_USER = mfs
WORKING_GROUP = mfs
DATA_PATH = /var/lib/mfs/gui
SYSLOG_MIN_LEVEL = ${mfsgui_log_level}
GUISERV_LISTEN_HOST = *
GUISERV_LISTEN_PORT = 9425
EOF

    if [[ -n "${gui_root_dir}" && -n "${gui_requests_file}" ]]; then
        cat <<EOF >> /etc/mfs/mfsgui.cfg
ROOT_DIR = ${gui_root_dir}
REQUESTS_FILE = ${gui_requests_file}
EOF
    fi
}

find_gui_entrypoint() {
    find /usr/share -type f -name 'mfs.cgi' -print -quit 2>/dev/null || true
}

patch_gui_defaults() {
    local master_host="${1}"
    local master_port="${2}"
    local cgi_path

    if [[ -z "${master_host}" ]]; then
        return
    fi

    cgi_path="$(find_gui_entrypoint)"
    if [[ -z "${cgi_path}" ]]; then
        bashio::log.warning \
            "Unable to locate mfs.cgi under /usr/share; MooseFS GUI will keep its upstream master defaults"
        return
    fi

    python3 - "${cgi_path}" "${master_host}" "${master_port}" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
master_host = sys.argv[2]
master_port = int(sys.argv[3])
text = path.read_text(encoding="utf-8")

updated = re.sub(
    r"^masterhost = .*$",
    f"masterhost = {master_host!r}",
    text,
    count=1,
    flags=re.MULTILINE,
)
updated = re.sub(
    r"^masterport = .*$",
    f"masterport = {master_port}",
    updated,
    count=1,
    flags=re.MULTILINE,
)

if updated != text:
    path.write_text(updated, encoding="utf-8")
PY

    bashio::log.info "Patched MooseFS GUI defaults in ${cgi_path} to ${master_host}:${master_port}"
}

log_mount_strategy() {
    local mount_point="${1}"
    local backup_dir="${2}"
    local media_dir="${3}"
    local share_dir="${4}"

    bashio::log.info \
        "Mount point ${mount_point} is internal to the add-on container; Home Assistant Ingress uses the lighttpd proxy on port 8099, the raw MooseFS GUI stays on port 9425, and the filesystem is exported over NFSv4 on port 2049"

    if [[ -n "${share_dir}" ]]; then
        bashio::log.info \
            "Supervisor share mount will target ${share_dir} inside the NFS export"
    else
        bashio::log.info "Supervisor share mount is disabled"
    fi

    if [[ -n "${backup_dir}" ]]; then
        bashio::log.info \
            "Supervisor backup mount will target ${backup_dir} inside the NFS export"
    fi

    if [[ -n "${media_dir}" ]]; then
        bashio::log.info \
            "Supervisor media mount will target ${media_dir} inside the NFS export"
    fi

    if [[ -z "${backup_dir}" ]]; then
        bashio::log.info "Supervisor backup mount is disabled"
    fi

    if [[ -z "${media_dir}" ]]; then
        bashio::log.info "Supervisor media mount is disabled"
    fi
}

write_proxy_config() {
    cat <<'EOF' > /etc/lighttpd/lighttpd.conf
server.modules = (
    "mod_access",
    "mod_proxy",
    "mod_rewrite"
)

server.document-root = "/var/lib/mfs/gui"
server.errorlog = "/dev/stderr"
server.port = 8099
server.bind = "0.0.0.0"

# Strip the Home Assistant ingress session prefix before forwarding to mfsgui.
url.rewrite-once = (
    "^/$" => "/mfs.cgi",
    "^/(api/)?hassio_ingress/[^/]+$" => "/mfs.cgi",
    "^/(api/)?hassio_ingress/[^/]+/$" => "/mfs.cgi",
    "^/(api/)?hassio_ingress/[^/]+/(.*)$" => "/$2"
)

proxy.server = (
    "" => (
        (
            "host" => "127.0.0.1",
            "port" => 9425
        )
    )
)

$HTTP["remoteip"] != "172.30.32.2" {
    url.access-deny = ( "" )
}
EOF
}

main() {
    local delayed_init
    local log_level
    local master_host
    local master_password
    local master_port
    local master_subfolder
    local mfsgui_log_level
    local mount_enabled
    local mount_point
    local backup_dir
    local media_dir
    local share_dir
    local gui_requests_path
    local gui_root_dir

    log_level="$(bashio::config 'log_level')"
    master_host="$(bashio::config 'master_host')"
    master_port="$(bashio::config 'master_port')"
    master_subfolder="$(bashio::config 'master_subfolder')"
    master_password="$(bashio::config 'master_password')"
    mount_point="$(bashio::config 'mount_point')"
    backup_dir="$(bashio::config 'backup_dir')"
    media_dir="$(bashio::config 'media_dir')"
    share_dir="$(bashio::config 'share_dir')"
    mount_enabled="$(bashio::config 'mount_enabled')"
    delayed_init="$(bashio::config 'delayed_init')"
    mfsgui_log_level="$(to_mfsgui_log_level "${log_level}")"
    gui_requests_path="$(find_gui_requests_file)"
    gui_root_dir="$(find_gui_root_dir)"

    bashio::log.info "Preparing MooseFS runtime configuration"
    bashio::log.info "Mount point: ${mount_point}"
    log_mount_strategy "${mount_point}" "${backup_dir}" "${media_dir}" "${share_dir}"

    if [[ -n "${gui_requests_path}" && -n "${gui_root_dir}" ]]; then
        bashio::log.info \
            "MooseFS GUI assets discovered under ${gui_root_dir} with request map ${gui_requests_path}"
    else
        bashio::log.warning \
            "Unable to locate MooseFS GUI requests.cfg under /usr/share; the GUI may load without full asset metadata"
    fi

    if [[ -n "${master_host}" ]]; then
        bashio::log.info "MooseFS master client endpoint: ${master_host}:${master_port}${master_subfolder}"
    else
        bashio::log.warning \
            "MooseFS master host is not configured yet; the GUI will stay up, but mount attempts will be skipped until master_host is set"
    fi

    mkdir -p \
        /etc/exports.d \
        /etc/mfs \
        /run/lighttpd \
        /run/moosefs \
        /var/lib/nfs/rpc_pipefs \
        /var/lib/mfs/gui \
        "${mount_point}"
    chown -R mfs:mfs /var/lib/mfs
    printf 'user_allow_other\n' > /etc/fuse.conf

    write_mount_config \
        "${master_host}" \
        "${master_port}" \
        "${master_subfolder}" \
        "${delayed_init}" \
        "${master_password}"
    write_nfs_exports "${mount_point}"
    write_gui_config \
        "${mfsgui_log_level}" \
        "${gui_root_dir}" \
        "${gui_requests_path##*/}"
    patch_gui_defaults "${master_host}" "${master_port}"
    write_proxy_config

    bashio::log.info \
        "Configured NFSv4 export for ${mount_point}; Supervisor mount sync will manage share/media/backup mounts from configured subdirectories once MooseFS is live"

    if is_true "${mount_enabled}" && [[ ! -e /dev/fuse ]]; then
        bashio::log.error "/dev/fuse is not available; the MooseFS mount service will keep retrying until it appears"
    fi
}
main "$@"
