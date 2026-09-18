{ config, lib, pkgs, ... }:

let
  # --- What gets backed up, and why ---------------------------------------
  # Included (encrypted, versioned, off-box once the drive is rotated):
  #   /data/backup-staging   consistent DB dumps (see dumpScript below)
  #   /data/nextcloud        Nextcloud user files
  #   /data/immich/upload    photo/video library
  #   /data/syncthing        synced files + Syncthing's own index/db
  #   /data/forgejo          git repositories + Forgejo state
  #   /data/vaultwarden/attachments  Vaultwarden file attachments
  # (Vaultwarden's *database* is backed up as a consistent sqlite3 .backup
  # copy in backup-staging, not by reading the live db.sqlite3 file.)
  #
  # Explicitly NOT included, on purpose:
  #   /data/media             Jellyfin's media library — large and
  #                            considered replaceable. If you keep
  #                            irreplaceable footage there, move it under
  #                            /data/nextcloud or /data/immich instead so
  #                            it's covered.
  #   /data/postgresql        raw live Postgres cluster files — never back
  #                            up a live database's files directly; the
  #                            pg_dump in backup-staging is the real backup.
  #   /data/immich/postgres   same reasoning — dumped via pg_dump instead.
  #   NixOS configuration     lives in Git, not here — Git IS its backup.
  #   The age secrets key     backed up out-of-band, deliberately never
  #                            inside the thing it protects — see
  #                            secrets/README.md and docs/backups.md.
  backupPaths = [
    "/data/backup-staging"
    "/data/nextcloud"
    "/data/immich/upload"
    "/data/syncthing"
    "/data/forgejo"
    "/data/vaultwarden/attachments"
  ];

  excludePatterns = [
    "*/appdata_*/preview/*" # Nextcloud thumbnail cache — regenerable
    "*.tmp"
  ];

  dumpScript = pkgs.writeShellScript "backup-predump" ''
    set -euo pipefail
    umask 077
    mkdir -p /data/backup-staging

    echo "Dumping Nextcloud (maintenance mode on)..."
    ${pkgs.nextcloud29}/bin/nextcloud-occ maintenance:mode --on
    ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_16}/bin/pg_dump nextcloud \
      | gzip > /data/backup-staging/nextcloud.sql.gz.tmp
    mv /data/backup-staging/nextcloud.sql.gz.tmp /data/backup-staging/nextcloud.sql.gz
    ${pkgs.nextcloud29}/bin/nextcloud-occ maintenance:mode --off

    echo "Dumping Forgejo..."
    ${pkgs.sudo}/bin/sudo -u postgres ${pkgs.postgresql_16}/bin/pg_dump forgejo \
      | gzip > /data/backup-staging/forgejo.sql.gz.tmp
    mv /data/backup-staging/forgejo.sql.gz.tmp /data/backup-staging/forgejo.sql.gz

    echo "Dumping Immich's database (in-container)..."
    ${pkgs.podman}/bin/podman exec immich-postgres \
      pg_dump -U immich immich | gzip > /data/backup-staging/immich.sql.gz.tmp
    mv /data/backup-staging/immich.sql.gz.tmp /data/backup-staging/immich.sql.gz

    echo "Snapshotting Vaultwarden's sqlite database..."
    ${pkgs.sqlite}/bin/sqlite3 /data/vaultwarden/db.sqlite3 \
      ".backup /data/backup-staging/vaultwarden.sqlite3.tmp"
    mv /data/backup-staging/vaultwarden.sqlite3.tmp /data/backup-staging/vaultwarden.sqlite3
  '';

  resticArgs = lib.concatStringsSep " " (map (p: "--exclude '${p}'") excludePatterns);
  textfileDir = "/var/lib/node_exporter/textfile";

  backupScript = pkgs.writeShellScript "backup-run" ''
    set -uo pipefail
    export RESTIC_REPOSITORY="/mnt/backup-usb/restic-repo"
    export RESTIC_PASSWORD_FILE="${config.sops.secrets."restic/password".path}"

    metrics="${textfileDir}/backup.prom.tmp"
    final="${textfileDir}/backup.prom"

    if ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/backup-usb; then
      echo "Backup USB drive is not connected — skipping this run."
      {
        echo "# HELP backup_repo_present Whether the backup USB drive is currently mounted"
        echo "backup_repo_present 0"
      } > "$metrics"
      mv "$metrics" "$final"
      # Not a failure — see docs/backups.md. BackupStale will alert if
      # this drops go on for more than 8 days.
      exit 0
    fi

    ${dumpScript}

    ${pkgs.restic}/bin/restic snapshots >/dev/null 2>&1 || ${pkgs.restic}/bin/restic init
    if ${pkgs.restic}/bin/restic backup ${resticArgs} ${lib.concatStringsSep " " backupPaths}; then
      success=1
    else
      success=0
    fi

    # Prune old snapshots: keep a sensible retention window without
    # letting the repo grow forever on a fixed-size USB drive.
    ${pkgs.restic}/bin/restic forget --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune || true

    {
      echo "# HELP backup_repo_present Whether the backup USB drive is currently mounted"
      echo "backup_repo_present 1"
      echo "# HELP backup_last_run_success Whether the most recent backup run succeeded"
      echo "backup_last_run_success $success"
    } > "$metrics"
    if [ "$success" = "1" ]; then
      echo "backup_last_success_timestamp_seconds $(date +%s)" >> "$metrics"
    fi
    mv "$metrics" "$final"

    exit $((1 - success))
  '';

  checkScript = pkgs.writeShellScript "backup-check" ''
    set -uo pipefail
    export RESTIC_REPOSITORY="/mnt/backup-usb/restic-repo"
    export RESTIC_PASSWORD_FILE="${config.sops.secrets."restic/password".path}"

    if ! ${pkgs.util-linux}/bin/mountpoint -q /mnt/backup-usb; then
      echo "Backup USB drive not connected — nothing to check right now."
      exit 0
    fi

    # Full structural check + read back a sample of actual data blocks
    # (not just metadata) so bit-rot on the USB drive gets caught.
    ${pkgs.restic}/bin/restic check --read-data-subset=10%
  '';
in
{
  sops.secrets."restic/password" = {
    sopsFile = ../../secrets/secrets.yaml;
    mode = "0400";
  };

  environment.systemPackages = [ pkgs.restic ];

  systemd.services.restic-backup = {
    description = "Restic backup to off-site USB drive";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${backupScript}";
    };
  };

  systemd.timers.restic-backup = {
    description = "Daily attempt to back up to the USB drive (a no-op if it's not plugged in)";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true; # catch up if the server was off at the scheduled time
      RandomizedDelaySec = "30m";
    };
  };

  systemd.services.restic-check = {
    description = "Verify backup repository integrity";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${checkScript}";
    };
  };

  systemd.timers.restic-check = {
    description = "Weekly backup verification";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
    };
  };
}
