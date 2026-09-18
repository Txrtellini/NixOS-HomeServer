# Home Server — NixOS Flake

A single bare-metal NixOS host running Nextcloud, Jellyfin, Immich,
Vaultwarden, Syncthing, Forgejo, AdGuard Home, and a monitoring +
backup stack, reachable on the LAN and via WireGuard only (no public
domain, nothing exposed to the internet). See `docs/architecture.md`
for the full design rationale.

## ⚠️ Before you deploy

This repository was authored in a sandboxed environment with no access
to `nix`, `cache.nixos.org`, or a NixOS evaluator — every file here was
written and manually reviewed for correct option names, syntax, and
cross-references, but **it has not been built or evaluated by an
actual Nix toolchain**. Before trusting it on real hardware:

```bash
nix flake check .
sudo nixos-rebuild build --flake .#server   # build, don't activate
```

Fix anything that surfaces there first. Every `YOUR_*` string in the
repo (`grep -rn "YOUR_" --include='*.nix' .`) is a placeholder you must
fill in — see `docs/installation.md`.

## What runs where

| App | Type | Reached at |
|---|---|---|
| Nextcloud | native NixOS module | `https://nextcloud.srv.home` |
| Jellyfin | native NixOS module | `https://jellyfin.srv.home` |
| Immich | Podman containers | `https://immich.srv.home` |
| Vaultwarden | native NixOS module | `https://vault.srv.home` |
| Syncthing | native NixOS module | `https://sync.srv.home` |
| Forgejo | native NixOS module | `https://git.srv.home` |
| AdGuard Home | native NixOS module | `https://adguard.srv.home` |
| Grafana | native NixOS module | `https://grafana.srv.home` |
| Uptime Kuma | Podman container | `https://uptime.srv.home` |

All of the above are reachable on your LAN directly, or from anywhere
via WireGuard (`modules/networking/wireguard.nix`) — never from the
open internet. See `docs/networking.md` for exactly which ports are
open and why.

Ollama and Open WebUI are defined but not enabled by default
(`modules/containers/ollama.nix`, `open-webui.nix`) — the core server
works fully without them.

## Where data lives

Everything under `/data` on the 4TB HDD, laid out per-app — see
`docs/storage.md`. Nothing application-specific lives on the system
SSD. The NixOS configuration itself lives here, in Git — that's its
backup.

## How to deploy

Fresh hardware → running server: `docs/installation.md`.

## How to update

```bash
nix flake update
sudo nixos-rebuild build --flake .#server    # review first
sudo nixos-rebuild switch --flake .#server
```

Full explanation, including container image version bumps and
Nextcloud major-version upgrades: `docs/upgrades.md`.

## How to roll back

```bash
sudo nixos-rebuild switch --rollback
```

or pick an older generation from the systemd-boot menu at startup.

## How backups work / how to restore

Restic, backing up to an external USB drive kept mostly off-site.
Design and the honest tradeoffs of that choice: `docs/backups.md`.
Restoring a single file, one app's data, or a database: `docs/restore.md`.
Rebuilding the entire server from nothing: `docs/disaster-recovery.md`.

## How to add a new service

1. Decide native NixOS module vs. container (default to native unless
   there's a specific reason not to — see `docs/architecture.md`).
2. Add a file under `modules/services/yourapp.nix` (native) or
   `modules/containers/yourapp.nix` (container), following the shape of
   an existing one in the same category.
3. Point its data directory at a new `/data/yourapp` — add the
   directory to `systemd.tmpfiles.rules` in `modules/storage/default.nix`
   with the right owner.
4. Add any credentials it needs to `secrets/secrets.yaml.example` and
   real `secrets/secrets.yaml` (see `secrets/README.md`), reference them
   via `sops.secrets."yourapp/..."`.
5. Add a Caddy vhost in `modules/networking/caddy.nix` and a DNS rewrite
   in `modules/networking/adguard.nix` if it needs a web UI reachable
   the same way as everything else.
6. Add its data paths to `backupPaths` in `modules/backups/default.nix`
   if the data is irreplaceable — and to the "explicitly NOT backed up"
   list in `docs/backups.md` if it deliberately isn't.
7. Import the new file from `modules/services/default.nix` or
   `modules/containers/default.nix`.
8. `sudo nixos-rebuild build --flake .#server`, review, then `switch`.

## Repository layout

```
flake.nix                    Pinned inputs, single host output
hosts/server/                Host identity, bootloader, hardware config
modules/base/                Nix settings, locale, GC
modules/networking/          Firewall, WireGuard, Caddy, AdGuard Home
modules/storage/             Filesystems, /data layout
modules/security/            Users, SSH hardening, fail2ban
modules/monitoring/          Prometheus, Grafana, Alertmanager, smartd, (optional UPS)
modules/backups/             Restic timers, DB dumps, verification
modules/services/            Native NixOS-module applications
modules/containers/          Podman applications (+ optional Ollama/Open WebUI)
secrets/                     sops-encrypted secrets.yaml + template + README
docs/                        Full documentation (see below)
```

## Documentation index

- `docs/architecture.md` — design and major decisions
- `docs/installation.md` — fresh-install deployment + validation commands
- `docs/storage.md` — disk layout, ZFS-vs-ext4 decision
- `docs/networking.md` — every open port, DNS, TLS without a domain
- `docs/backups.md` — full backup strategy and its tradeoffs
- `docs/restore.md` — restoring individual files/apps/databases
- `docs/upgrades.md` — flake updates, generations, rollback
- `docs/disaster-recovery.md` — full rebuild + failure-scenario runbook
- `docs/security.md` — security model, Podman-vs-Docker, why not Kubernetes

## Maintenance

**Monthly:**
- Skim `journalctl -p err -b` for anything that's been quietly failing.
- Confirm `restic-backup` has a recent success:
  `curl -s http://127.0.0.1:9100/metrics | grep backup_last_success`.
- Check `systemctl --failed` is empty.
- Glance at the Grafana dashboard for disk space / memory trends.

**Quarterly:**
- `nix flake update`, review the diff, build, test, switch
  (`docs/upgrades.md`).
- Actually run a test restore of one file per `docs/restore.md` — a
  backup you've never restored from isn't a verified backup.
- Rotate the off-site USB drive if you haven't been doing so weekly.
- Review `secrets/secrets.yaml` for anything that should be rotated
  (Vaultwarden's admin token, the Restic password, etc.).
