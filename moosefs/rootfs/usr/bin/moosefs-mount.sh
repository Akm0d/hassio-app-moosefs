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

mount_is_active() {
    local mount_point="${1}"
    local fstype

    fstype="$(findmnt -n -o FSTYPE --target "${mount_point}" 2>/dev/null || true)"
    [[ "${fstype}" == moosefs || "${fstype}" == fuse.moosefs || "${fstype}" == fuse.mfsmount ]]
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

master_is_reachable() {
    local master_host="${1}"
    local master_port="${2}"
    local result

    if [[ -z "${master_host}" ]]; then
        bashio::log.warning "MooseFS master host is empty; skipping mount attempt until master_host is configured"
        return 1
    fi

    if result="$(python3 - "${master_host}" "${master_port}" <<'PY'
import socket
import sys

master_host = sys.argv[1]
master_port = int(sys.argv[2])

try:
    socket.getaddrinfo(master_host, master_port, type=socket.SOCK_STREAM)
except socket.gaierror:
    print("unresolvable")
    raise SystemExit(2)

try:
    with socket.create_connection((master_host, master_port), timeout=3):
        pass
except OSError:
    print("unreachable")
    raise SystemExit(3)

print("ok")
PY
    )"; then
        return 0
    fi

    case "${result}" in
        unresolvable)
            bashio::log.warning \
                "MooseFS master ${master_host}:${master_port} is not resolvable from the add-on container; skipping mount attempt"
            ;;
        unreachable)
            bashio::log.warning \
                "MooseFS master ${master_host}:${master_port} is not accepting TCP connections from the add-on container; skipping mount attempt. Use the MooseFS client port (usually 9421), not the GUI/web port."
            ;;
        *)
            bashio::log.warning \
                "MooseFS master ${master_host}:${master_port} is not reachable from the add-on container; skipping mount attempt"
            ;;
    esac
    return 1
}

log_mount_listing() {
    local mount_point="${1}"
    local ls_output

    if ! ls_output="$(ls -lhtr "${mount_point}" 2>&1)"; then
        bashio::log.warning "MooseFS mount at ${mount_point} exists but is not readable yet: ${ls_output}"
        return 1
    fi

    bashio::log.info "MooseFS mount is live at ${mount_point}; top-level listing follows"
    while IFS= read -r line; do
        if [[ -n "${line}" ]]; then
            bashio::log.info "${line}"
        fi
    done <<< "${ls_output:-total 0}"
}

wait_for_mount_ready() {
    local mount_point="${1}"
    local mfsmount_pid="${2}"
    local attempt

    for attempt in $(seq 1 30); do
        if ! kill -0 "${mfsmount_pid}" 2>/dev/null; then
            return 1
        fi

        if mount_is_active "${mount_point}" && log_mount_listing "${mount_point}"; then
            return 0
        fi

        sleep 1
    done

    bashio::log.warning "Timed out waiting for MooseFS mount at ${mount_point} to become readable"
    return 1
}

main() {
    local mount_enabled
    local master_host
    local master_port
    local mfsmount_pid
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

        if ! master_is_reachable "${master_host}" "${master_port}"; then
            sleep 15
            continue
        fi

        bashio::log.info "Starting MooseFS mount at ${mount_point}"

        /usr/bin/mfsmount -f -c /etc/mfs/mfsmount.cfg "${mount_point}" &
        mfsmount_pid=$!

        wait_for_mount_ready "${mount_point}" "${mfsmount_pid}" || true

        if wait "${mfsmount_pid}"; then
            bashio::log.warning "MooseFS mount process exited cleanly; retrying in 15 seconds"
        else
            bashio::log.warning "MooseFS mount process exited with an error; retrying in 15 seconds"
        fi

        sleep 15
    done
}
main "$@"
