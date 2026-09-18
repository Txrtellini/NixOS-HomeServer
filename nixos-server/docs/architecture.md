# Architecture

## Overview

One bare-metal box, two disks (256GB SSD for the OS, 4TB HDD for
application data), reachable on the LAN directly and from anywhere else
only through WireGuard. Everything is defined in this Git repository as
a Nix flake; nothing is configured by hand on the running machine except
a handful of genuinely one-time, interactive steps (documented explicitly
wherever they occur — AdGuard Home's admin password, Syncthing device
pairing, Vaultwarden account creation).

```
Internet
   │
   ▼ (WireGuard UDP 51820, forwarded by your router)
┌─────────────────────────────────────────────────────────┐
│ NixOS host                                               │
│                                                           │
│  wg0 (10.100.0.1/24) ──┐                                 │
│  LAN  (YOUR_SERVER_LAN_IP) ─┤──► Caddy :443 (tls internal)│
│                          │        │                       │
│                          │        ├─ nextcloud.srv.home ─►│ nginx:8081 ─► Nextcloud (native)
│                          │        ├─ jellyfin.srv.home  ─►│ Jellyfin (native) :8096
│                          │        ├─ immich.srv.home    ─►│ Immich (containers) :2283
│                          │        ├─ vault.srv.home     ─►│ Vaultwarden (native) :8000
│                          │        ├─ sync.srv.home      ─►│ Syncthing (native) :8384
│                          │        ├─ git.srv.home       ─►│ Forgejo (native) :3001
│                          │        ├─ grafana.srv.home   ─►│ Grafana (native) :3000
│                          │        ├─ uptime.srv.home    ─►│ Uptime Kuma (container) :3002
│                          │        └─ adguard.srv.home   ─►│ AdGuard Home admin UI :3033
│                          │                                │
│                          └──► AdGuard Home :53 (DNS for LAN + WireGuard clients)
│                                                           │
│  PostgreSQL (native, shared) ── Nextcloud DB, Forgejo DB  │
│  Immich's own Postgres+Redis (containers)                 │
│                                                           │
│  Prometheus ── node_exporter, smartctl_exporter            │
│  Grafana ── dashboards                                     │
│  Alertmanager ── email on critical conditions               │
│                                                           │
│  Restic ── daily timer, backs up to /mnt/backup-usb         │
│            when the drive is plugged in                    │
└─────────────────────────────────────────────────────────┘
    │                              │
    ▼                              ▼
 SSD: / (LVM+ext4)            HDD: /data (ext4)
                                    external USB: /mnt/backup-usb (Restic repo, off-site most of the time)
```

## Why this shape

- **One host, no orchestration.** A single machine doesn't need
  Kubernetes, Swarm, or any scheduler — there's nothing to schedule
  *across*. See "Why Kubernetes is excluded" in `docs/security.md`'s
  sibling discussion, repeated here: the complexity Kubernetes adds
  (etcd, a control plane, CNI, ingress controllers, its own upgrade
  cadence) has no corresponding benefit on one box, and every one of
  those components would itself need monitoring, backing up, and
  upgrading — pure configuration debt against your stated priorities.

- **NixOS modules over Kubernetes/Compose.** A NixOS module is a
  declarative, typed description of a systemd service, validated at
  build time. That's strictly more "declarative and reproducible" than
  a Compose file or a Helm chart, and it's what NixOS is *for*.

- **Native services first, containers when there's a real reason.**
  Nextcloud, Vaultwarden, Syncthing, Forgejo, Jellyfin, Caddy, AdGuard
  Home, Prometheus, Grafana, PostgreSQL all have mature native NixOS
  modules — using them means one less runtime (no container engine
  involved at all for most of the system), and systemd handles restart
  behavior, resource limits, and dependency ordering uniformly.
  Immich and Uptime Kuma are containerized because neither has a
  workable native module: Immich's upstream architecture is a
  multi-container stack built around a specific Postgres+pgvector
  image tied to its own release cadence, and Uptime Kuma has no native
  packaging at all.

- **Podman, never Docker.** See `docs/security.md`.

- **ext4, not ZFS.** See `docs/storage.md`.

- **Restic, one tool, one job.** See `docs/backups.md`.

## What each module directory is for

| Directory | Responsibility |
|---|---|
| `modules/base` | Nix settings, locale, GC, minimal base packages |
| `modules/networking` | Interfaces, firewall, WireGuard, Caddy, AdGuard Home |
| `modules/storage` | Filesystems, `/data` layout, tmpfiles ownership |
| `modules/security` | Users, SSH hardening, fail2ban, container privilege boundary |
| `modules/monitoring` | Prometheus, exporters, Grafana, Alertmanager, smartd |
| `modules/backups` | Restic timers, pre-backup DB dumps, verification, metrics |
| `modules/services` | Native NixOS-module applications |
| `modules/containers` | Podman/OCI applications (Immich, Uptime Kuma, optional Ollama/Open WebUI) |

## What's inherently mutable, and how it's handled

Nix makes the *system* reproducible — packages, services, users,
firewall rules, filesystem mounts. It does not and cannot make
*application data* reproducible, because that data is generated by you
using the apps (photos, git commits, password entries, sync state,
database rows). That data:

- lives entirely under `/data`, never inside a container's writable
  layer or a package's `/nix/store` path, so recreating the *system*
  (`nixos-rebuild switch`) never touches it;
- is covered by the Restic backup strategy in `docs/backups.md`;
- is restored by a completely separate procedure
  (`docs/restore.md`/`docs/disaster-recovery.md`) from the *system*
  restore, because "rebuild the OS" and "recover the data" are
  different operations with different tools.

Databases are a special case of mutable state — see the "database
strategy" section of `docs/backups.md` for why raw file copies of a
live database are never used here.
