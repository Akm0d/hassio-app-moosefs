# Home Assistant Add-on: MooseFS

This repository contains a Home Assistant add-on that mounts a MooseFS share
with `mfsmount` and exposes the MooseFS GUI through Home Assistant Ingress.

The add-on is designed so the GUI can stay up even if the FUSE mount is broken
or the master is unavailable during boot. By default it mounts MooseFS at
`/share/moosefs`, which gives the best chance of making the mounted tree
available to the Home Assistant host as well.

See [the add-on documentation](./moosefs/DOCS.md) for installation and
configuration details.
