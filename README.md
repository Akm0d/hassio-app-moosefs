# Home Assistant Add-on: MooseFS

This repository contains a Home Assistant add-on that mounts a MooseFS share
with `mfsmount` and exposes the MooseFS GUI through Home Assistant Ingress.

The add-on is designed so the GUI can stay up even if the FUSE mount is broken
or the master is unavailable during boot. By default it mounts MooseFS at
`/mnt/mfs` inside the add-on container and exports that same directory over
NFSv4 on TCP `2049`. The Home Assistant sidebar goes through the internal
`lighttpd` ingress proxy, while `OPEN WEB UI` goes straight to the MooseFS GUI
at `http://<host>:9425/mfs.cgi`.

See [the add-on documentation](./moosefs/DOCS.md) for installation and
configuration details.
