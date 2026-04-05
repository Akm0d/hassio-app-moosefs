# Home Assistant Add-on: MooseFS

This add-on mounts a MooseFS share inside Home Assistant and exposes the
MooseFS GUI through Home Assistant Ingress. The GUI stays available even if
the client mount is down or still reconnecting.

## What It Does

- Builds MooseFS from upstream source for the add-on image.
- Starts `mfsgui` inside the container on `0.0.0.0:9425`.
- Uses `lighttpd` on port `8099` only for Home Assistant Ingress/sidebar
  access.
- Exposes the raw MooseFS GUI directly on `http://<home-assistant-host>:9425/`
  via `/mfs.cgi` for the `OPEN WEB UI` button.
- Mounts MooseFS with `mfsmount` into a writable path that defaults to
  `/share/mfs`, using Home Assistant's standard writable `share` mapping.
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
mount_point: /share/mfs
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
Default: `/share/mfs`.

This add-on follows the same Home Assistant mapping convention used by add-ons
like Plex: writable `/share`, writable `/media`, and read-only `/ssl`.
MooseFS uses a nested FUSE mount, so with the default `mount_point: /share/mfs`
the underlying host path is also `/share/mfs`, but whether the live MooseFS
FUSE mount itself appears on the host depends on Supervisor mount propagation
and may remain container-only.

If you change `mount_point` to a path under `/media`, the underlying host path
matches there too. If you change it to a path outside `/share` or `/media`,
the mount will remain private to the add-on container.

### Option: `mount_enabled`

Enables or disables the MooseFS client mount loop. When disabled, the GUI still
starts.

### Option: `delayed_init`

Adds MooseFS delayed initialization to the mount so the client can come up even
before the master is reachable. This is enabled by default to keep boot more
resilient.

## Access Paths

- Home Assistant sidebar tab: goes through Ingress to the add-on proxy on
  `8099`.
- `OPEN WEB UI`: goes directly to `http://<home-assistant-host>:9425/mfs.cgi`.
- Underlying host path for the default mount point: `/share/mfs`.

## Notes

- This add-on needs `/dev/fuse`, `SYS_ADMIN`, and AppArmor disabled because the
  MooseFS client uses FUSE mounts.
- If the mount fails, the add-on keeps the web UI alive and retries the mount
  every 15 seconds.
- The add-on logs `ls -lhtr` output for the mount point after the MooseFS mount
  becomes readable, which is the quickest way to confirm that the container can
  actually see files there.
- If `master_host` is empty or cannot be resolved from the add-on container,
  the add-on leaves the GUI running and skips mount attempts until the setting
  is corrected.
- If the Home Assistant sidebar still shows `404 Not Found`, use `OPEN WEB UI`
  and inspect the add-on logs. Recent MooseFS releases ship the GUI through
  `mfsgui`, so this add-on now leaves the GUI content paths on the upstream
  defaults instead of pinning the older CGI layout.
- If `/share/mfs` is mounted in the container but `/share/mfs` is empty on the
  host, that points to mount propagation rather than a MooseFS login problem.
  In that case the add-on can still use MooseFS internally, but Home Assistant
  may not surface the nested FUSE mount back onto the host namespace.

## Changelog & Releases

This repository uses GitHub releases for version history.
