#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: MooseFS
# Generate runtime configuration for the GUI, proxy, and mount services.
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

write_gui_config() {
    local mfsgui_log_level="${1}"

    cat <<EOF > /etc/mfs/mfsgui.cfg
WORKING_USER = mfs
WORKING_GROUP = mfs
DATA_PATH = /var/lib/mfs/gui
SYSLOG_MIN_LEVEL = ${mfsgui_log_level}
GUISERV_LISTEN_HOST = *
GUISERV_LISTEN_PORT = 9425
EOF
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

log_host_mount_mapping() {
    local mount_point="${1}"

    if [[ "${mount_point}" == /mnt/* ]]; then
        bashio::log.info \
            "Mount points under /mnt are backed by Home Assistant's share directory at /share${mount_point#/mnt}; whether a nested MooseFS FUSE mount becomes visible on the host depends on Supervisor mount propagation"
    else
        bashio::log.warning \
            "Mount point ${mount_point} is outside /mnt, so the MooseFS mount will stay internal to the add-on container"
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

    log_level="$(bashio::config 'log_level')"
    master_host="$(bashio::config 'master_host')"
    master_port="$(bashio::config 'master_port')"
    master_subfolder="$(bashio::config 'master_subfolder')"
    master_password="$(bashio::config 'master_password')"
    mount_point="$(bashio::config 'mount_point')"
    mount_enabled="$(bashio::config 'mount_enabled')"
    delayed_init="$(bashio::config 'delayed_init')"
    mfsgui_log_level="$(to_mfsgui_log_level "${log_level}")"

    bashio::log.info "Preparing MooseFS runtime configuration"
    bashio::log.info "Mount point: ${mount_point}"
    log_host_mount_mapping "${mount_point}"

    if [[ -n "${master_host}" ]]; then
        bashio::log.info "MooseFS master client endpoint: ${master_host}:${master_port}${master_subfolder}"
    else
        bashio::log.warning \
            "MooseFS master host is not configured yet; the GUI will stay up, but mount attempts will be skipped until master_host is set"
    fi

    mkdir -p \
        /etc/mfs \
        /run/lighttpd \
        /run/moosefs \
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
    write_gui_config "${mfsgui_log_level}"
    patch_gui_defaults "${master_host}" "${master_port}"
    write_proxy_config

    if is_true "${mount_enabled}" && [[ ! -e /dev/fuse ]]; then
        bashio::log.error "/dev/fuse is not available; the MooseFS mount service will keep retrying until it appears"
    fi
}
main "$@"
