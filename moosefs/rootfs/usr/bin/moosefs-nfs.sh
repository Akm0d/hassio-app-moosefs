#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: MooseFS
# Export the MooseFS mount over NFSv4.
# ==============================================================================

set -euo pipefail

is_true() {
    [[ "${1}" == "true" ]]
}

mount_is_active() {
    local mount_point="${1}"

    mountpoint -q "${mount_point}" 2>/dev/null
}

cleanup() {
    local exit_code=$?

    set +e

    if [[ -n "${idmapd_pid:-}" ]]; then
        kill "${idmapd_pid}" 2>/dev/null || true
        wait "${idmapd_pid}" 2>/dev/null || true
    fi

    exportfs -ua 2>/dev/null || true
    rpc.nfsd 0 2>/dev/null || true
    umount /proc/fs/nfsd 2>/dev/null || true
    umount /var/lib/nfs/rpc_pipefs 2>/dev/null || true

    exit "${exit_code}"
}

main() {
    local mount_enabled
    local mount_point

    mount_enabled="$(bashio::config 'mount_enabled')"
    mount_point="$(bashio::config 'mount_point')"

    if ! is_true "${mount_enabled}"; then
        bashio::log.notice "NFS export is disabled because the MooseFS mount loop is disabled"
        exec sleep infinity
    fi

    trap cleanup EXIT INT TERM

    bashio::log.info "Waiting for MooseFS mount at ${mount_point} before starting NFSv4 export"
    until mount_is_active "${mount_point}"; do
        sleep 2
    done

    mkdir -p /var/lib/nfs/rpc_pipefs
    mountpoint -q /var/lib/nfs/rpc_pipefs || mount -t rpc_pipefs rpc_pipefs /var/lib/nfs/rpc_pipefs
    mountpoint -q /proc/fs/nfsd || mount -t nfsd nfsd /proc/fs/nfsd

    bashio::log.info "Publishing ${mount_point} as the NFSv4 root export on tcp/2049"
    exportfs -r

    # NFSv4 does not require rpc.mountd, so keep the service to the minimum:
    # id mapping plus the kernel nfsd threads.
    rpc.idmapd -S -f &
    idmapd_pid=$!

    # Serve NFSv4 only over TCP. rpc.nfsd takes the trailing "8" as the number
    # of server threads to start.
    rpc.nfsd -N 3 -U 8
    wait "${idmapd_pid}"
}
main "$@"
