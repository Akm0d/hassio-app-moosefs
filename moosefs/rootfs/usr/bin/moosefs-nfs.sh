#!/command/with-contenv bashio
# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: MooseFS
# Export the MooseFS mount over NFS.
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

    for pid_var in mountd_pid idmapd_pid rpcbind_pid; do
        if [[ -n "${!pid_var:-}" ]]; then
            kill "${!pid_var}" 2>/dev/null || true
            wait "${!pid_var}" 2>/dev/null || true
        fi
    done

    exportfs -ua 2>/dev/null || true
    rpc.nfsd 0 2>/dev/null || true
    umount /proc/fs/nfsd 2>/dev/null || true
    umount /var/lib/nfs/rpc_pipefs 2>/dev/null || true

    exit "${exit_code}"
}

main() {
    local backup_dir
    local media_dir
    local mount_enabled
    local mount_point
    local share_dir

    backup_dir="$(bashio::config 'backup_dir')"
    media_dir="$(bashio::config 'media_dir')"
    mount_enabled="$(bashio::config 'mount_enabled')"
    mount_point="$(bashio::config 'mount_point')"
    share_dir="$(bashio::config 'share_dir')"

    if ! is_true "${mount_enabled}"; then
        bashio::log.notice "NFS export is disabled because the MooseFS mount loop is disabled"
        exec sleep infinity
    fi

    trap cleanup EXIT INT TERM

    bashio::log.info "Waiting for MooseFS mount at ${mount_point} before starting NFS export"
    until mount_is_active "${mount_point}"; do
        sleep 2
    done

    mkdir -p /run/rpcbind
    mkdir -p /var/lib/nfs/rpc_pipefs
    mountpoint -q /var/lib/nfs/rpc_pipefs || mount -t rpc_pipefs rpc_pipefs /var/lib/nfs/rpc_pipefs
    mountpoint -q /proc/fs/nfsd || mount -t nfsd nfsd /proc/fs/nfsd

    if timeout 3 rpcinfo -p 127.0.0.1 >/dev/null 2>&1; then
        bashio::log.info "Using existing rpcbind service on localhost:111"
    else
        bashio::log.info "Starting rpcbind on localhost:111 for NFS service discovery"
        rpcbind -f -w &
        rpcbind_pid=$!

        for _ in $(seq 1 10); do
            if timeout 3 rpcinfo -p 127.0.0.1 >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done

        if ! timeout 3 rpcinfo -p 127.0.0.1 >/dev/null 2>&1; then
            bashio::log.error "rpcbind did not become reachable on localhost:111"
            exit 1
        fi
    fi

    bashio::log.info "Publishing ${mount_point} as the NFS export on localhost:2049"
    exportfs -r

    bashio::log.info "Starting rpc.mountd and rpc.idmapd for Home Assistant compatibility"
    rpc.mountd -F -N 2 &
    mountd_pid=$!
    rpc.idmapd -S -f &
    idmapd_pid=$!

    # Start a standard Linux NFS server. Keeping both v3 and v4 available makes
    # Home Assistant's generic mount.nfs client much more predictable.
    rpc.nfsd 8

    while IFS= read -r line; do
        [[ -n "${line}" ]] && bashio::log.info "exportfs: ${line}"
    done < <(exportfs -v 2>/dev/null || true)

    while IFS= read -r line; do
        [[ -n "${line}" ]] && bashio::log.info "rpcinfo: ${line}"
    done < <(timeout 5 rpcinfo -p 127.0.0.1 2>/dev/null || true)

    if ! python3 /usr/bin/moosefs-supervisor-mounts.py \
        "${mount_point}" \
        "${share_dir}" \
        "${media_dir}" \
        "${backup_dir}"; then
        bashio::log.warning \
            "Supervisor mount synchronization failed; the NFS export is still live on tcp/2049"
    fi

    wait "${idmapd_pid}"
}
main "$@"
