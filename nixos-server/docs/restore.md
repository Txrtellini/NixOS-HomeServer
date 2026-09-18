# Restoring individual files or application data

For a total server rebuild, see `docs/disaster-recovery.md` instead —
this page is for "I deleted a file" or "Nextcloud's upgrade broke
something," not "the server is gone."

All commands assume the backup USB drive is connected and mounted at
`/mnt/backup-usb`, and are run as root (or via `sudo`) on the server.

```bash
export RESTIC_REPOSITORY=/mnt/backup-usb/restic-repo
export RESTIC_PASSWORD_FILE=/run/secrets/restic/password  # sops-nix's decrypted path
```

## List snapshots

```bash
restic snapshots
```

## Restore a single file (e.g. an accidentally deleted photo)

```bash
# Find it first:
restic find "IMG_1234.jpg"

# Restore just that path from the latest snapshot into a scratch directory
# (never restore directly over live data without checking it first):
restic restore latest --target /root/restore-scratch --include /data/immich/upload/IMG_1234.jpg

# Once you've confirmed it's right, copy it into place with the correct
# ownership:
install -o immich -g immich /root/restore-scratch/data/immich/upload/IMG_1234.jpg /data/immich/upload/
```

## Restore an entire application's data directory

Example: Nextcloud, after a bad upgrade corrupted files.

```bash
systemctl stop phpfpm-nextcloud.service nginx.service

mv /data/nextcloud /data/nextcloud.broken   # keep the broken copy until you're sure

restic restore latest --target / --include /data/nextcloud

chown -R nextcloud:nextcloud /data/nextcloud
systemctl start phpfpm-nextcloud.service nginx.service
```

The same pattern (stop the service, restore the directory, fix
ownership, start the service) applies to `/data/syncthing`,
`/data/forgejo`, `/data/vaultwarden/attachments`, and
`/data/immich/upload` — substitute the relevant `systemctl` unit names
(`syncthing.service`, `forgejo.service`, `vaultwarden.service`; Immich's
containers are `podman-immich-server.service` etc.).

## Restore a database from its dump

Databases are backed up as `pg_dump`/sqlite `.backup` output inside
`/data/backup-staging`, not as raw files — restoring means loading that
dump back in, not just copying files back.

### PostgreSQL (Nextcloud or Forgejo)

```bash
restic restore latest --target /root/restore-scratch --include /data/backup-staging/nextcloud.sql.gz

systemctl stop phpfpm-nextcloud.service

sudo -u postgres dropdb nextcloud
sudo -u postgres createdb -O nextcloud nextcloud
zcat /root/restore-scratch/data/backup-staging/nextcloud.sql.gz | sudo -u postgres psql nextcloud

systemctl start phpfpm-nextcloud.service
```

Same shape for `forgejo.sql.gz` (stop `forgejo.service` first, restore
into the `forgejo` database, restart it).

### Immich's database (inside its container)

```bash
restic restore latest --target /root/restore-scratch --include /data/backup-staging/immich.sql.gz

systemctl stop podman-immich-server.service podman-immich-ml.service

zcat /root/restore-scratch/data/backup-staging/immich.sql.gz | podman exec -i immich-postgres psql -U immich immich

systemctl start podman-immich-server.service podman-immich-ml.service
```

### Vaultwarden (sqlite)

```bash
restic restore latest --target /root/restore-scratch --include /data/backup-staging/vaultwarden.sqlite3

systemctl stop vaultwarden.service
cp /root/restore-scratch/data/backup-staging/vaultwarden.sqlite3 /data/vaultwarden/db.sqlite3
chown vaultwarden:vaultwarden /data/vaultwarden/db.sqlite3
systemctl start vaultwarden.service
```

## Restoring an older snapshot instead of the latest

Replace `latest` with a snapshot ID from `restic snapshots` in any
command above, e.g. `restic restore a1b2c3d4 --target ...`.
