# Home Assistant Add-on: MooseFS

This repository contains a Home Assistant add-on that mounts a MooseFS share
with `mfsmount` and exposes the MooseFS GUI through Home Assistant Ingress.

The add-on is designed so the GUI can stay up even if the FUSE mount is broken
or the master is unavailable during boot. By default it mounts MooseFS at
`/mnt/mfs` inside the add-on container, and it can optionally proxy the GUI on
port `8099` for direct browser access.

See [the add-on documentation](./moosefs/DOCS.md) for installation and
configuration details.
