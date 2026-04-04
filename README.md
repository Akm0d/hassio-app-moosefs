# Home Assistant Add-on: MooseFS

This repository contains a Home Assistant add-on that mounts a MooseFS share
with `mfsmount` and exposes the MooseFS GUI through Home Assistant Ingress.

The add-on is designed so the GUI can stay up even if the FUSE mount is broken
or the master is unavailable during boot. By default it mounts MooseFS at
`/media/mfs`, and it also exposes the Home Assistant `/share` folder if you
prefer to mount there instead.

See [the add-on documentation](./moosefs/DOCS.md) for installation and
configuration details.
