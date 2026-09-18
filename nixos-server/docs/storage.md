# Storage

## Physical layout

- **SSD (256GB)** — the system disk. Partitioned as a small EFI System
  Partition (`/boot`) plus an LVM volume group holding the root
  filesystem. LVM buys you the ability to resize `/` later without
  repartitioning, at negligible complexity cost.
- **HDD (4TB)** — application data, mounted at `/data`. See the layout
  table below.
- **External USB drive** — the Restic backup repository, mounted at
  `/mnt/backup-usb` only when physically connected (it lives off-site
  most of the time). See `docs/backups.md`.

## Filesystem choice: ext4, not ZFS

This was a genuine decision, not a default. The case for ZFS is real —
checksumming, cheap snapshots, send/receive, and (with a mirror) silent
corruption protection are all things ext4 doesn't offer. It was
rejected for this specific single-server, single-data-disk deployment
for concrete reasons:

1. **No redundancy target.** ZFS's headline reliability feature
   (protection against silent bit-rot via redundancy + checksums) needs
   at least two disks in a mirror/raidz to actually recover from a bad
   checksum, not just detect one. With one data disk, ZFS can tell you
   a block is corrupt but can't fix it — you're relying on Restic
   either way for recovery from real damage.
2. **You already have a real backup strategy.** The thing that actually
   protects this data — an encrypted, versioned, off-box copy — is
   Restic, independent of filesystem choice. ZFS snapshots are useful
   but are explicitly *not* a backup (see `docs/backups.md`): they live
   on the same disk and don't survive that disk failing.
3. **Operational surface area.** ZFS on NixOS works well, but it adds
   real things to understand and maintain for years: pool import
   ordering at boot, ARC memory sizing (relevant on a box that's also
   running a dozen services), scrub scheduling, `zfs list`/`zpool
   status` as a second storage vocabulary alongside the standard Linux
   one, and the fact that ZFS is a Linux kernel module built
   out-of-tree (DKMS-style), so a NixOS channel bump can occasionally
   race ahead of ZFS support. None of this is disqualifying on a
   multi-disk pool where redundancy matters — it's not proportionate
   here.
4. **Priorities.** Your stated order is reliability → reproducibility →
   security → recoverability → maintainability → simplicity → learning
   value, with an explicit instruction not to optimize for novelty.
   ext4 + LVM is about as close to "everyone already understands this,
   every rescue tool already supports it, nothing about it will
   surprise you in three years" as Linux storage gets.

**If your situation changes** — you add a second or third HDD and want
pooled redundancy, or you want cheap frequent local snapshots as a fast
"undo" layer in addition to (not instead of) Restic — ZFS becomes a
much stronger case, and this module structure (`modules/storage`) is
where you'd swap it in. It's a reasonable thing to revisit later; it
just isn't the right default for one HDD.

## `/data` layout

```
/data/
├── nextcloud/          Nextcloud data directory
├── media/               Jellyfin's media library (movies/, tv/, music/) — NOT backed up, see docs/backups.md
├── jellyfin/            Jellyfin config/metadata/cache
├── immich/
│   ├── upload/           photo/video library
│   └── postgres/         Immich's own Postgres data (container bind mount)
├── vaultwarden/         sqlite db + attachments
├── syncthing/           synced folders + index database
├── forgejo/             git repositories + Forgejo state
├── postgresql/          shared PostgreSQL cluster (Nextcloud + Forgejo databases)
├── uptime-kuma/         Uptime Kuma's sqlite db
└── backup-staging/      transient pg_dump/sqlite-backup output, written fresh before each Restic run
```

Ownership for each directory is set declaratively via
`systemd.tmpfiles.rules` in `modules/storage/default.nix` — matching
each service's own system user, so a fresh `nixos-rebuild switch` on
brand-new hardware recreates correct permissions without any manual
`chown`.

Nothing here writes application data into `/var/lib/<service>` on the
system SSD, and nothing writes it into a container's writable layer —
every service's data-directory option is explicitly redirected into
`/data`, so container recreation, package upgrades, and even a full SSD
replacement never touch application data.
