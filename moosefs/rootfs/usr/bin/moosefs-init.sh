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
GUISERV_LISTEN_HOST = 127.0.0.1
GUISERV_LISTEN_PORT = 9425
ROOT_DIR = /usr/share/mfscgi
REQUESTS_FILE = requests.cfg
EOF
}

write_proxy_config() {
    local allow_direct_webui="${1}"

    cat <<'EOF' > /etc/lighttpd/lighttpd.conf
server.modules = (
    "mod_access",
    "mod_proxy"
)

server.document-root = "/usr/share/mfscgi"
server.errorlog = "/dev/stderr"
server.port = 8099
server.bind = "0.0.0.0"
server.username = "root"
server.groupname = "root"

proxy.server = (
    "" => (
        (
            "host" => "127.0.0.1",
            "port" => 9425
        )
    )
)
EOF

    if ! is_true "${allow_direct_webui}"; then
        cat <<'EOF' >> /etc/lighttpd/lighttpd.conf

$HTTP["remoteip"] != "172.30.32.2" {
    url.access-deny = ( "" )
}
EOF
    fi
}

check_share_propagation() {
    local mount_point="${1}"
    local propagation

    if [[ "${mount_point}" != /share* ]]; then
        return
    fi

    propagation="$(findmnt -n -o PROPAGATION --target /share 2>/dev/null || true)"
    case "${propagation}" in
        shared|rshared|slave|rslave)
            bashio::log.info "Share mount propagation detected as: ${propagation}"
            ;;
        *)
            bashio::log.warning \
                "Share mount propagation is '${propagation:-unknown}'. Nested MooseFS mounts may stay private to the add-on and not appear on the host."
            ;;
    esac
}

main() {
    local allow_direct_webui
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
    allow_direct_webui="$(bashio::config 'allow_direct_webui')"
    mfsgui_log_level="$(to_mfsgui_log_level "${log_level}")"

    bashio::log.info "Preparing MooseFS runtime configuration"
    bashio::log.info "MooseFS master: ${master_host}:${master_port}${master_subfolder}"
    bashio::log.info "Mount point: ${mount_point}"

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
    write_proxy_config "${allow_direct_webui}"
    check_share_propagation "${mount_point}"

    if is_true "${mount_enabled}" && [[ ! -e /dev/fuse ]]; then
        bashio::log.error "/dev/fuse is not available; the MooseFS mount service will keep retrying until it appears"
    fi
}
main "$@"
