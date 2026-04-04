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

    if ! mountpoint -q "${mount_point}" 2>/dev/null; then
        return
    fi

    fstype="$(findmnt -n -o FSTYPE --target "${mount_point}" 2>/dev/null || true)"
    if [[ "${fstype}" == moosefs || "${fstype}" == fuse.moosefs || "${fstype}" == fuse.mfsmount ]]; then
        bashio::log.warning "Unmounting stale MooseFS mount from ${mount_point}"
        fusermount3 -u "${mount_point}" 2>/dev/null || umount "${mount_point}" 2>/dev/null || true
    fi
}

main() {
    local mount_enabled
    local mount_point

    mount_enabled="$(bashio::config 'mount_enabled')"
    mount_point="$(bashio::config 'mount_point')"

    if ! is_true "${mount_enabled}"; then
        bashio::log.notice "MooseFS mount loop is disabled"
        exec sleep infinity
    fi

    mkdir -p "${mount_point}"

    while true; do
        cleanup_existing_mount "${mount_point}"
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
