# Disaster Recovery

## What you need to rebuild from nothing

Assume the server is destroyed completely (stolen, burned, whatever).
Recovery needs exactly four things, none of which live only on the
dead machine:

1. A fresh NixOS installer (any USB stick with the current NixOS ISO).
2. This Git repository (pushed to Forgejo *and* to a remote outside
   this server — GitHub, a friend's Forgejo, anywhere off-box; a Git
   repo whose only remote was the dead server isn't recoverable).
3. The sops age private key (`secrets/README.md` — backed up
   out-of-band, not inside the Restic repository).
4. The Restic backup repository (the external USB drive).

## Full rebuild procedure

### 1. Install NixOS

Boot the NixOS installer, partition the new SSD and HDD to match
`hosts/server/hardware-configuration.nix`'s expected layout (documented
in that file), then:

```bash
nixos-generate-config --root /mnt
# copy the generated /mnt/etc/nixos/hardware-configuration.nix content
# into this repo's hosts/server/hardware-configuration.nix afterward —
# for now, a minimal default install is enough to get a working system
# you can SSH into.
nixos-install
reboot
```

### 2. Get the repository onto the new machine

```bash
git clone <your-remote-url> /etc/nixos-server
cd /etc/nixos-server
# paste the real hardware-configuration.nix generated above into
# hosts/server/hardware-configuration.nix
```

### 3. Restore the secrets key

```bash
sudo mkdir -p /var/lib/sops-nix
sudo cp /path/to/your/backed-up/key.txt /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt
```

### 4. Fill in hardware-specific placeholders

Go through every `YOUR_*` placeholder in the repo (grep for it) —
disk UUIDs (`blkid`), network interface name (`ip link`), LAN IP,
WireGuard keys, etc. — and fill in real values for this specific
machine.

### 5. Build and activate

```bash
sudo nixos-rebuild switch --flake .#server
```

This brings up every service, but with **empty** `/data` — the apps
exist, but there's no user data yet.

### 6. Restore data from the backup drive

Plug in the USB backup drive.

```bash
export RESTIC_REPOSITORY=/mnt/backup-usb/restic-repo
export RESTIC_PASSWORD_FILE=/run/secrets/restic/password

# Stop everything that touches /data first:
sudo systemctl stop phpfpm-nextcloud nginx vaultwarden syncthing forgejo \
  podman-immich-server podman-immich-ml podman-immich-postgres podman-immich-redis \
  podman-uptime-kuma postgresql

sudo restic restore latest --target /

sudo systemctl start postgresql
```

### 7. Restore the databases from their dumps

Postgres is now running with the restored (but empty, freshly
initialized by `services.postgresql`) cluster structure — load the
actual data from the dumps that were restored into
`/data/backup-staging`:

```bash
sudo -u postgres dropdb nextcloud && sudo -u postgres createdb -O nextcloud nextcloud
zcat /data/backup-staging/nextcloud.sql.gz | sudo -u postgres psql nextcloud

sudo -u postgres dropdb forgejo && sudo -u postgres createdb -O forgejo forgejo
zcat /data/backup-staging/forgejo.sql.gz | sudo -u postgres psql forgejo
```

Start everything else back up:

```bash
sudo systemctl start phpfpm-nextcloud nginx vaultwarden syncthing forgejo \
  podman-immich-postgres podman-immich-redis podman-immich-server podman-immich-ml \
  podman-uptime-kuma
```

Immich's database restore happens inside its own container after its
Postgres container is up:

```bash
zcat /data/backup-staging/immich.sql.gz | podman exec -i immich-postgres psql -U immich immich
```

Vaultwarden's database file was restored directly as part of step 6
(it's just a file, not a live-service dump target) — confirm it's at
`/data/vaultwarden/db.sqlite3` with the right ownership.

### 8. Verify

Run through `docs/installation.md`'s validation section, then actually
log into each app and spot-check that your real data is there.

## Failure scenario runbook

**A native service crashes** (e.g. Vaultwarden). systemd's `Restart =
"on-failure"` (set per-service across this repo) brings it back
automatically. Check `systemctl status vaultwarden` and `journalctl -u
vaultwarden -e` if it keeps crash-looping.

**A container crashes** (Immich, Uptime Kuma). Same mechanism —
`Restart = "on-failure"` on the generated `podman-*.service` units.
`journalctl -u podman-immich-server -e` and `podman logs immich-server`
for container-internal errors.

**A disk starts failing.** `smartd` and the `smartctl_exporter` /
`SmartFailure` Prometheus alert should catch this before total failure.
Back up anything not yet in a Restic snapshot immediately (plug in the
USB drive, run `systemctl start restic-backup`), order a replacement,
and follow standard LVM/ext4 disk-replacement steps for whichever disk
failed — this is the one case where the specific procedure genuinely
depends on which disk failed and your exact partition layout at the
time.

**The main SSD dies.** The OS is entirely reproducible from Git — this
is the scenario this whole architecture is built around. Install a new
SSD, follow "Full rebuild procedure" above, minus the "restore /data"
steps if the HDD survived (just re-mount it) or including them if it
didn't.

**The entire server dies.** Follow "Full rebuild procedure" above, in
full.

**A bad NixOS configuration is deployed.**
`sudo nixos-rebuild switch --rollback`, or pick a specific prior
generation from the boot menu at startup. See `docs/upgrades.md`.

**A package upgrade breaks a service.** Roll back the same way
(`nixos-rebuild switch --rollback`), then pin that package's version or
investigate the breakage on a separate test before retrying the
upgrade. Never re-run the same upgrade expecting a different result.

**A database becomes corrupted.** Stop the affected service, restore
its database from the most recent good dump per `docs/restore.md`,
accepting the data loss between that dump and the corruption
(minimized by the daily backup cadence — see `docs/backups.md`'s
discussion of recovery point objective).

**A backup job fails for several days.** `BackupFailed` (drive was
connected, Restic errored) or `BackupStale` (no successful run in 8+
days) fires in Alertmanager. For `BackupFailed`, check
`journalctl -u restic-backup -e` — common causes are the drive filling
up (`df -h /mnt/backup-usb`) or a stale lock from an interrupted run
(`restic unlock`). For `BackupStale`, just plug the drive back in.

**The server is compromised.** Disconnect it from the network
immediately (pull the LAN cable / disable the interface at the
router). Do not trust anything on the running system for forensics.
Treat this the same as "the entire server dies": rebuild from Git +
the age key + the Restic backup on new or freshly-wiped hardware,
rotate every secret in `secrets/secrets.yaml` (new passwords, new
WireGuard keys, new Restic repository password — note that rotating
the Restic password means re-encrypting or recreating the repository,
so do this on a healthy system, not reactively during the incident if
avoidable), and only restore application *data* (which a compromise of
the host doesn't necessarily corrupt) after the new system is up and
verified secure.

**The router/DNS configuration breaks.** This server's own services
don't depend on your router beyond basic LAN connectivity and the
WireGuard port-forward. If AdGuard Home (this server's own DNS) is
itself down or misconfigured, LAN devices lose name resolution for
`*.srv.home` — set a fallback DNS server on your router/devices (e.g.
9.9.9.9) so general internet access isn't held hostage by this
server's DNS role, and access services by IP (`https://
YOUR_SERVER_LAN_IP`) until AdGuard Home is fixed.

**A power outage occurs.** With a UPS configured (`modules/monitoring/
ups.nix`, optional — see that file), a brief outage is transparent and
a prolonged one triggers a clean shutdown before the battery dies.
Without a UPS, an outage is a hard power-cut: ext4 with a journal
recovers cleanly in the overwhelming majority of cases on next boot,
but this is real risk of filesystem or database corruption during
active writes that a UPS would have prevented — worth budgeting for a
UPS if outages aren't rare where you live.
