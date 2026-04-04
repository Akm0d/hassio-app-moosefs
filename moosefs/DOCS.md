# Home Assistant Add-on: MooseFS

This add-on mounts a MooseFS share inside Home Assistant and exposes the
MooseFS GUI through Home Assistant Ingress. The GUI stays available even if
the client mount is down or still reconnecting.

## What It Does

- Builds MooseFS from upstream source for the add-on image.
- Starts `mfsgui` locally inside the container on `127.0.0.1:9425`.
- Publishes the GUI through `lighttpd` on port `8099` for Home Assistant
  Ingress.
- Mounts MooseFS with `mfsmount` into a writable path that defaults to
  `/share/moosefs`.
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
mount_point: /share/moosefs
mount_enabled: true
delayed_init: true
allow_direct_webui: false
```

### Option: `master_host`

Resolvable hostname or IP address of the MooseFS master.

Leave this empty until you know the correct value. The GUI will still start,
but the add-on will skip mount attempts until `master_host` is configured.

### Option: `master_port`

Client port on the MooseFS master. Default: `9421`.

### Option: `master_subfolder`

Subdirectory inside MooseFS to mount. Use `/` for the full tree.

### Option: `master_password`

Optional MooseFS export password. Leave empty when the export does not require
one.

### Option: `mount_point`

Absolute path inside the add-on container where MooseFS should be mounted.
Default: `/share/moosefs`.

If you keep the default, the add-on mounts into Home Assistant's shared folder
mapping. That is the best path for making the mount visible on the host, but
whether the nested FUSE mount propagates back to the host depends on the bind
propagation configured by Supervisor on that system. The add-on logs a warning
when `/share` does not appear to be using shared or slave propagation.

### Option: `mount_enabled`

Enables or disables the MooseFS client mount loop. When disabled, the GUI still
starts.

### Option: `delayed_init`

Adds MooseFS delayed initialization to the mount so the client can come up even
before the master is reachable. This is enabled by default to keep boot more
resilient.

### Option: `allow_direct_webui`

When `false`, the reverse proxy only accepts requests from Home Assistant
Ingress. When `true`, the add-on will also allow direct access through the
optional port mapping for `8099/tcp`.

If you enable this, also enable the `8099/tcp` network port in the add-on's
Network settings.

## Notes

- This add-on needs `/dev/fuse`, `SYS_ADMIN`, and AppArmor disabled because the
  MooseFS client uses FUSE mounts.
- If the mount fails, the add-on keeps the web UI alive and retries the mount
  every 15 seconds.
- If `master_host` is empty or cannot be resolved from the add-on container,
  the add-on leaves the GUI running and skips mount attempts until the setting
  is corrected.
- Home Assistant Ingress is the primary supported UI path.

## Changelog & Releases

This repository uses GitHub releases for version history.
