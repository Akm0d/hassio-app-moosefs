#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: MooseFS
# Keep the MooseFS mount alive without taking down the GUI stack on failure.
# ==============================================================================

set -euo pipefail

is_true() {
    [[ "${1}" == "true" ]]
}

cleanup_existing_mount() {
    local mount_point="${1}"
    local fstype

    fstype="$(findmnt -n -o FSTYPE --target "${mount_point}" 2>/dev/null || true)"
    if [[ -z "${fstype}" ]]; then
        return
    fi

    if [[ "${fstype}" == moosefs || "${fstype}" == fuse.moosefs || "${fstype}" == fuse.mfsmount ]]; then
        bashio::log.warning "Unmounting stale MooseFS mount from ${mount_point}"
        fusermount3 -u "${mount_point}" 2>/dev/null \
            || umount "${mount_point}" 2>/dev/null \
            || umount -l "${mount_point}" 2>/dev/null \
            || true
    fi
}

master_is_resolvable() {
    local master_host="${1}"
    local master_port="${2}"

    if [[ -z "${master_host}" ]]; then
        bashio::log.warning "MooseFS master host is empty; skipping mount attempt until master_host is configured"
        return 1
    fi

    if python3 - "${master_host}" "${master_port}" <<'PY'
import socket
import sys

master_host = sys.argv[1]
master_port = int(sys.argv[2])

try:
    socket.getaddrinfo(master_host, master_port, type=socket.SOCK_STREAM)
except OSError:
    raise SystemExit(1)
PY
    then
        return 0
    fi

    bashio::log.warning \
        "MooseFS master ${master_host}:${master_port} is not resolvable from the add-on container; skipping mount attempt"
    return 1
}

main() {
    local mount_enabled
    local master_host
    local master_port
    local mount_point

    mount_enabled="$(bashio::config 'mount_enabled')"
    master_host="$(bashio::config 'master_host')"
    master_port="$(bashio::config 'master_port')"
    mount_point="$(bashio::config 'mount_point')"

    if ! is_true "${mount_enabled}"; then
        bashio::log.notice "MooseFS mount loop is disabled"
        exec sleep infinity
    fi

    mkdir -p "${mount_point}"

    while true; do
        cleanup_existing_mount "${mount_point}"

        if ! master_is_resolvable "${master_host}" "${master_port}"; then
            sleep 15
            continue
        fi

        bashio::log.info "Starting MooseFS mount at ${mount_point}"

        if /usr/bin/mfsmount -f -c /etc/mfs/mfsmount.cfg "${mount_point}"; then
            bashio::log.warning "MooseFS mount process exited cleanly; retrying in 15 seconds"
        else
            bashio::log.warning "MooseFS mount process exited with an error; retrying in 15 seconds"
        fi

        sleep 15
    done
}
main "$@"
