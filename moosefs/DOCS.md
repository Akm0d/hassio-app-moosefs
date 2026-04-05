# Home Assistant Add-on: MooseFS

This add-on mounts a MooseFS share inside Home Assistant and exposes the
MooseFS GUI through Home Assistant Ingress. The GUI stays available even if
the client mount is down or still reconnecting.

## What It Does

- Builds MooseFS from upstream source for the add-on image.
- Starts `mfsgui` inside the container on `0.0.0.0:9425`.
- Uses `lighttpd` on internal port `8099` for Home Assistant Ingress/sidebar
  access.
- Exposes the raw MooseFS GUI directly on `http://<home-assistant-host>:9425/`
  via `/mfs.cgi` for the `OPEN WEB UI` button.
- Mounts MooseFS with `mfsmount` into a writable path that defaults to
  `/mnt/mfs` inside the add-on container.
- Exports the MooseFS mount over NFSv4 on TCP port `2049` so clients can mount
  it explicitly.
- Keeps retrying the mount in the background instead of failing the whole
  add-on startup.

## Installation

1. Add this repository to Home Assistant.
1. Install the `MooseFS` add-on.
1. Set `master_host` to a resolvable DNS name or IP address for your MooseFS master.
1. Start the add-on.
1. Open the add-on panel from Home Assistant or use `OPEN WEB UI`.

## Configuration

```yaml
log_level: info
master_host: mfsmaster.lan
master_port: 9421
master_subfolder: /
master_password: ""
mount_point: /mnt/mfs
mount_enabled: true
delayed_init: true
```

### Option: `master_host`

Resolvable hostname or IP address of the MooseFS master.

Leave this empty until you know the correct value. The GUI will still start,
but the add-on will skip mount attempts until `master_host` is configured.

### Option: `master_port`

Client protocol port on the MooseFS master. Default: `9421`.

This is not the web UI port. The MooseFS GUI typically listens on `9425`,
while `mfsmount` and `mfscli` talk to the master client port, which is usually
`9421`.

### Option: `master_subfolder`

Subdirectory inside MooseFS to mount. Use `/` for the full tree.

### Option: `master_password`

Optional MooseFS export password. Leave empty when the export does not require
one.

### Option: `mount_point`

Absolute path inside the add-on container where MooseFS should be mounted.
Default: `/mnt/mfs`.

The MooseFS client mount is intentionally internal to the add-on container.
This add-on exports that internal mount over NFSv4 instead of trying to
propagate the FUSE mount back through a Home Assistant host bind.

If you change `mount_point`, the NFS export follows that exact internal path.

### Option: `mount_enabled`

Enables or disables the MooseFS client mount loop. When disabled, the GUI still
starts.

### Option: `delayed_init`

Adds MooseFS delayed initialization to the mount so the client can come up even
before the master is reachable. This is enabled by default to keep boot more
resilient.

## Access Paths

- Home Assistant sidebar tab: goes through Home Assistant Ingress to the
  `lighttpd` proxy on `8099`.
- `OPEN WEB UI`: goes directly to `http://<home-assistant-host>:9425/mfs.cgi`.
- NFSv4 export root: `server:/` on TCP `2049`, backed by the internal
  MooseFS mount at `/mnt/mfs`.

## Mounting Over NFS

On another Linux system, or on the Home Assistant host if you have host shell
access, mount the add-on export with:

```sh
mkdir -p /mnt/mfs
mount -t nfs4 -o vers=4.2,proto=tcp <home-assistant-host>:/ /mnt/mfs
```

Example:

```sh
mount -t nfs4 -o vers=4.2,proto=tcp hearth.goose-stargazer.ts.net:/ /mnt/mfs
```

The NFS export is read-write and intentionally uses `no_root_squash` so a root
client can manage files normally. Restrict network access to port `2049` to
trusted clients only.

## Notes

- This add-on needs `/dev/fuse`, `SYS_ADMIN`, and a custom AppArmor profile
  because the MooseFS client uses FUSE mounts and the NFS export mounts
  `rpc_pipefs` and `nfsd`.
- If the mount fails, the add-on keeps the web UI alive and retries the mount
  every 15 seconds.
- The add-on logs `ls -lhtr` output for the mount point after the MooseFS mount
  becomes readable, which is the quickest way to confirm that the container can
  actually see files there.
- The add-on waits for MooseFS to mount and then publishes the same path over
  NFSv4 using `exportfs`, `rpc.mountd`, `rpc.idmapd`, and `rpc.nfsd`.
- If `master_host` is empty or cannot be resolved from the add-on container,
  the add-on leaves the GUI running and skips mount attempts until the setting
  is corrected.
- If the Home Assistant sidebar still shows `404 Not Found`, inspect the add-on
  logs and confirm `lighttpd` is listening on `8099` and proxying to `mfsgui`
  on `9425`.

## Changelog & Releases

This repository uses GitHub releases for version history.
