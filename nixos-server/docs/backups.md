# Backups

## Tool: Restic, one repository, one strategy

Restic is the only backup tool in this configuration. It's
content-addressed, deduplicating, natively encrypted, and has a single
well-tested `check` command for verifying repository integrity — no
need to stack multiple backup tools on top of each other.

## Where backups go, and the tradeoff that comes with it

You chose an external USB drive, manually rotated off-site, as the
backup target. Being direct about what that does and doesn't give you:

- **What it protects against well:** accidental deletion, a bad
  `rm -rf`, a corrupted file, a failed Nextcloud upgrade that mangles
  data, ransomware that only touches the live HDD, and — because the
  drive spends most of its time physically elsewhere — the SSD or HDD
  failing, or the server itself being stolen or destroyed (fire, flood,
  power surge that fries both internal disks).
- **What it doesn't protect against:** data loss in the window since
  your last swap. If you plug the drive in weekly, your worst case is
  up to ~1 week of data loss in a true disaster. If you forget for a
  month, it's a month. This is a real, ongoing tradeoff of "free, no
  subscription" against "recovery point objective is only as good as
  your last swap." **Recommended cadence: plug in and sync weekly, at
  minimum.**
- **Single point of failure:** with one external drive, if it fails
  while it's your only off-site copy, you'd need to restore from
  whatever's newest before that failure. Two alternating drives (A at
  home syncing, B off-site, swap periodically so there's always one
  drive away from the house) closes this gap at the cost of buying a
  second drive — worth doing once you can.
- **The `BackupStale` alert** (see `modules/monitoring/alerts.nix`)
  fires if 8 days pass with no successful backup, specifically so a
  forgotten rotation shows up as an actual alert rather than silent
  drift.

The system is explicitly designed to degrade gracefully when the drive
is unplugged: the mount is `nofail`+`noauto`, the daily timer's script
detects the drive is absent, records that fact as a Prometheus metric
(`backup_repo_present 0`), and exits successfully rather than logging a
false "backup failed" every single day it's not home.

## What gets backed up

| Path | Contents | Why |
|---|---|---|
| `/data/backup-staging/*.sql.gz` | Consistent `pg_dump` output for Nextcloud, Forgejo, Immich | Proper database backups — never raw live database files (see below) |
| `/data/backup-staging/vaultwarden.sqlite3` | Consistent `sqlite3 .backup` snapshot | Same reasoning, sqlite-specific |
| `/data/nextcloud` | Nextcloud user files | Irreplaceable user data |
| `/data/immich/upload` | Photo/video library | Irreplaceable |
| `/data/syncthing` | Synced files + Syncthing's own index | User data + app state |
| `/data/forgejo` | Git repositories + Forgejo state | Irreplaceable (or at least expensive to reconstruct) |
| `/data/vaultwarden/attachments` | Vaultwarden file attachments | Irreplaceable |

## What is explicitly NOT backed up, and why

- **`/data/media`** (Jellyfin's library) — large, and treated as
  replaceable (rip/redownload). If you store anything irreplaceable
  there, move it under `/data/nextcloud` or `/data/immich` instead.
- **`/data/postgresql`** and **`/data/immich/postgres`** — the *live*
  database files. Copying a database's on-disk files while it's running
  is not a valid backup: you can capture a file mid-write and get an
  internally inconsistent copy that looks fine until you try to restore
  it. Every database here is instead dumped with `pg_dump` (or, for
  Vaultwarden, sqlite's own `.backup` command) into
  `/data/backup-staging` *before* Restic runs, which is a
  point-in-time-consistent logical export. Nextcloud is additionally
  put into maintenance mode for the few seconds the dump takes, so no
  write can land mid-dump.
- **The NixOS configuration itself** — it's not "backed up" via Restic
  because Git already is its backup, and a better one: full history,
  not just the latest snapshot.
- **The sops age private key** (`/var/lib/sops-nix/key.txt`) —
  deliberately excluded from the Restic repository. Restic's own
  repository password is itself one of the secrets that key decrypts,
  so backing the key up *inside* the thing it unlocks would be
  circular: if you lost the key, you'd need the key to get the key.
  Back it up out-of-band instead — see `secrets/README.md`.

## Encryption

Every Restic snapshot is encrypted client-side with a repository
password stored as a sops secret (`restic/password`) — the data on the
USB drive is unreadable without that password, so a lost or stolen
drive doesn't expose anything.

## Automation and verification

- `restic-backup.timer` — daily (systemd `OnCalendar=daily`,
  `Persistent=true` so a missed run catches up at next boot,
  `RandomizedDelaySec=30m` to avoid always hitting the exact same
  instant). Runs the pre-backup dumps, then `restic backup`, then
  `restic forget --prune` to enforce retention (14 daily / 8 weekly /
  12 monthly snapshots).
- `restic-check.timer` — weekly. Runs `restic check
  --read-data-subset=10%`, which verifies repository structure *and*
  reads back a rotating 10% sample of actual data blocks, so
  slow bit-rot on the USB drive gets caught well before you'd
  otherwise notice.
- **Failure detection**: both the daily run's outcome and its
  timestamp are published as Prometheus metrics via the node_exporter
  textfile collector (`backup_last_run_success`,
  `backup_last_success_timestamp_seconds`, `backup_repo_present`).
  Prometheus alerting rules (`modules/monitoring/alerts.nix`) turn
  those into two distinct alerts: `BackupFailed` (the drive was
  connected and Restic actually errored — urgent) and `BackupStale`
  (no successful backup in 8+ days — likely just "time to rotate the
  drive," but worth knowing).

## Rebuilding from scratch

The complete "server is gone" procedure — fresh install, Git clone, age
key restore, Restic restore — is in `docs/disaster-recovery.md`. Restoring
individual files or one application's data without reinstalling anything
is in `docs/restore.md`.
