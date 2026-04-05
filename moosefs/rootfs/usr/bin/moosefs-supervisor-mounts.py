#!/usr/bin/env python3
"""Synchronize Home Assistant Supervisor mounts for MooseFS."""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


SUPERVISOR_URL = "http://supervisor"
MANAGED_MOUNTS = {
    "share": "moosefs_share",
    "media": "moosefs_media",
    "backup": "moosefs_backup",
}


def log(level: str, message: str) -> None:
    print(f"{level}: {message}", flush=True)


def normalize_relative_dir(raw_value: str, *, default_root: bool) -> str | None:
    value = (raw_value or "").strip()
    if value in {"", ".", "/"}:
        return "" if default_root else None

    while value.startswith("./"):
        value = value[2:]

    value = value.lstrip("/").rstrip("/")

    if value in {"", "."}:
        return "" if default_root else None

    parts = []
    for part in value.split("/"):
        if part in {"", "."}:
            continue
        if part == "..":
            raise ValueError(f"directory '{raw_value}' must stay inside the MooseFS mount")
        parts.append(part)

    if not parts:
        return "" if default_root else None

    return "/".join(parts)


def nfs_path(relative_dir: str) -> str:
    if relative_dir == "":
        return "/"
    return f"/{relative_dir}"


def ensure_directory(mount_point: Path, relative_dir: str | None, purpose: str) -> None:
    if relative_dir in {None, ""}:
        return

    target = mount_point.joinpath(*relative_dir.split("/"))
    target.mkdir(parents=True, exist_ok=True)
    log("INFO", f"Ensured MooseFS directory for {purpose}: {target}")


def api_request(token: str, method: str, path: str, payload: dict | None = None):
    body = None
    headers = {"Authorization": f"Bearer {token}"}
    if payload is not None:
        body = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        f"{SUPERVISOR_URL}{path}",
        data=body,
        headers=headers,
        method=method,
    )

    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            raw = response.read().decode("utf-8").strip()
    except urllib.error.HTTPError as err:
        details = err.read().decode("utf-8", errors="replace").strip()
        raise RuntimeError(f"{method} {path} failed with HTTP {err.code}: {details}") from err
    except urllib.error.URLError as err:
        raise RuntimeError(f"{method} {path} failed: {err.reason}") from err

    if not raw:
        return None

    parsed = json.loads(raw)
    if isinstance(parsed, dict) and parsed.get("result") == "error":
        raise RuntimeError(f"{method} {path} failed: {parsed.get('message', parsed)}")
    if isinstance(parsed, dict) and "data" in parsed:
        return parsed["data"]
    return parsed


def mount_payload(name: str, usage: str, path: str) -> dict:
    payload = {
        "usage": usage,
        "type": "nfs",
        "server": "127.0.0.1",
        "port": 2049,
        "path": path,
        "read_only": False,
    }
    if usage != "backup":
        payload["read_only"] = False
    if name:
        payload["name"] = name
    return payload


def sync_mount(token: str, existing_mounts: dict, *, name: str, usage: str, path: str) -> None:
    payload = mount_payload("", usage, path)
    existing = existing_mounts.get(name)

    if existing is None:
        create_payload = mount_payload(name, usage, path)
        api_request(token, "POST", "/mounts", create_payload)
        log("INFO", f"Created Supervisor {usage} mount '{name}' for NFS path {path}")
        return

    api_request(token, "PUT", f"/mounts/{name}", payload)
    log("INFO", f"Updated Supervisor {usage} mount '{name}' for NFS path {path}")


def delete_mount(token: str, name: str, usage: str) -> None:
    api_request(token, "DELETE", f"/mounts/{name}")
    log("INFO", f"Removed Supervisor {usage} mount '{name}' because it is disabled")


def main() -> int:
    if len(sys.argv) != 5:
        log("ERROR", "usage: moosefs-supervisor-mounts.py <mount_point> <share_dir> <media_dir> <backup_dir>")
        return 2

    token = os.environ.get("SUPERVISOR_TOKEN", "")
    if not token:
        log("ERROR", "SUPERVISOR_TOKEN is not available; cannot synchronize Supervisor mounts")
        return 1

    mount_point = Path(sys.argv[1])
    share_dir = normalize_relative_dir(sys.argv[2], default_root=True)
    media_dir = normalize_relative_dir(sys.argv[3], default_root=False)
    backup_dir = normalize_relative_dir(sys.argv[4], default_root=False)

    ensure_directory(mount_point, share_dir, "share")
    ensure_directory(mount_point, media_dir, "media")
    ensure_directory(mount_point, backup_dir, "backup")

    mounts_info = api_request(token, "GET", "/mounts") or {}
    existing_mounts = {
        mount["name"]: mount
        for mount in mounts_info.get("mounts", [])
        if mount.get("name") in MANAGED_MOUNTS.values()
    }
    default_backup_mount = mounts_info.get("default_backup_mount")

    desired = {
        "share": share_dir,
        "media": media_dir,
        "backup": backup_dir,
    }

    if backup_dir is None and default_backup_mount == MANAGED_MOUNTS["backup"]:
        api_request(token, "POST", "/mounts/options", {"default_backup_mount": None})
        log("INFO", "Cleared default backup mount because moosefs_backup is disabled")

    for usage, relative_dir in desired.items():
        name = MANAGED_MOUNTS[usage]
        if relative_dir is None:
            if name in existing_mounts:
                delete_mount(token, name, usage)
            continue

        sync_mount(token, existing_mounts, name=name, usage=usage, path=nfs_path(relative_dir))

        if usage == "backup" and default_backup_mount != name:
            api_request(token, "POST", "/mounts/options", {"default_backup_mount": name})
            log("INFO", "Set moosefs_backup as the default Home Assistant backup mount")

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except ValueError as err:
        log("ERROR", str(err))
        raise SystemExit(1)
    except RuntimeError as err:
        log("ERROR", str(err))
        raise SystemExit(1)
