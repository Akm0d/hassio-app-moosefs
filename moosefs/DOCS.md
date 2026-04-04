# Home Assistant Add-on: MooseFS

This add-on mounts a MooseFS share inside Home Assistant and exposes the
MooseFS GUI through Home Assistant Ingress. The GUI stays available even if
the client mount is down or still reconnecting.

## What It Does

- Builds MooseFS from upstream source for the add-on image.
- Starts `mfsgui` inside the container on `0.0.0.0:9425` for Home Assistant
  Ingress.
- Optionally publishes the same GUI through `lighttpd` on port `8099` for
  direct browser access outside Ingress.
- Mounts MooseFS with `mfsmount` into a writable path that defaults to
  `/mnt/mfs`.
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
allow_direct_webui: false
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

The default is intentionally internal to the add-on container. MooseFS uses a
nested FUSE mount, and Home Assistant does not reliably surface those nested
mounts back onto the host through add-on bind mappings.

The add-on still exposes the Home Assistant `/media` and `/share` folders if
you want to experiment with mounting there, but whether the nested FUSE mount
propagates back to the host depends on Supervisor bind propagation. If you pick
one of those mapped paths, the add-on logs a warning when the parent path does
not appear to be using shared or slave propagation.

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

## Home Assistant Storage

Home Assistant network storage only supports NFS and Samba/CIFS targets. When
you add one of those in `Settings > System > Storage`, Home Assistant creates a
directory for it under `/media` or `/share`.

Because this add-on mounts MooseFS through FUSE inside the add-on container, it
does not automatically become a Home Assistant network storage target, and this
add-on does not currently auto-export that mount back to Home Assistant over
NFS or Samba.

If you need Home Assistant to treat MooseFS as network storage, use one of
these patterns:

1. Mount MooseFS on another machine and export it over NFS or Samba/CIFS, then
   add that export in `Settings > System > Storage`.
1. Mount MooseFS inside this add-on at `/mnt/mfs` and use a separate exporter
   solution that you manage yourself to publish `/mnt/mfs` over NFS or Samba.

This add-on does not automate the second pattern because Home Assistant cannot
self-register arbitrary exports as storage, and an in-container NFS/Samba
server needs additional service and kernel-level setup that is outside the
current add-on scope.

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
- Home Assistant Ingress is the primary supported UI path.

## Changelog & Releases

This repository uses GitHub releases for version history.
