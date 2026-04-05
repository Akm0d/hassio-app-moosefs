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

config_to_remote_path() {
    local raw_value="${1}"
    local slash_means_root="${2}"
    local value

    value="$(printf '%s' "${raw_value}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -z "${value}" ]]; then
        return 1
    fi

    if [[ "${value}" == "/" ]]; then
        if [[ "${slash_means_root}" == "true" ]]; then
            printf '/\n'
            return 0
        fi
        return 1
    fi

    while [[ "${value}" == ./* ]]; do
        value="${value#./}"
    done

    value="${value#/}"
    value="${value%/}"

    if [[ -z "${value}" || "${value}" == "." ]]; then
        if [[ "${slash_means_root}" == "true" ]]; then
            printf '/\n'
            return 0
        fi
        return 1
    fi

    printf '/%s\n' "${value}"
}

probe_nfs_path() {
    local remote_path="${1}"
    local purpose="${2}"
    local probe_dir="/run/moosefs/nfs-probe/${purpose}"
    local attempt

    mkdir -p "${probe_dir}"

    for attempt in $(seq 1 12); do
        umount "${probe_dir}" 2>/dev/null || true

        if timeout 10 mount -t nfs -o nfsvers=4.2,proto=tcp "127.0.0.1:${remote_path}" "${probe_dir}" >/dev/null 2>&1; then
            bashio::log.info "Verified local NFS path ${remote_path} for ${purpose}"
            umount "${probe_dir}" 2>/dev/null || true
            return 0
        fi

        bashio::log.info \
            "Waiting for local NFS path ${remote_path} to become mountable for ${purpose} (attempt ${attempt}/12)"
        sleep 5
    done

    bashio::log.warning \
        "Local NFS path ${remote_path} for ${purpose} did not become mountable before Supervisor sync"
    return 1
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
    local remote_path
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

    probe_nfs_path "/" "root" || true

    if remote_path="$(config_to_remote_path "${share_dir}" true)"; then
        if [[ "${remote_path}" != "/" ]]; then
            probe_nfs_path "${remote_path}" "share" || true
        fi
    fi

    if remote_path="$(config_to_remote_path "${media_dir}" false)"; then
        probe_nfs_path "${remote_path}" "media" || true
    fi

    if remote_path="$(config_to_remote_path "${backup_dir}" false)"; then
        probe_nfs_path "${remote_path}" "backup" || true
    fi

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
