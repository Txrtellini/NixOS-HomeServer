{ config, lib, pkgs, ... }:

{
  # --- Filesystem choice: ext4, not ZFS -----------------------------------
  # See docs/storage.md for the full comparison. Short version: this is a
  # single HDD with no redundancy target, real protection against data
  # loss comes from the encrypted off-box Restic backups (modules/backups),
  # and ZFS's extra moving parts (ARC sizing, ashift/pool import ordering,
  # ZFS-on-root boot complexity, ZFS never being fully in-tree) buy little
  # here while working against "simplicity" and "years without
  # configuration debt". Plain LVM + ext4 is fully mainline, boring, and
  # every recovery tool already understands it.

  # Data disk (4TB HDD) — application data lives here, never on the
  # system SSD. Replace DATA_HDD_UUID with the real UUID from `blkid`
  # once the disk is formatted (see docs/installation.md).
  fileSystems."/data" = {
    device = "/dev/disk/by-uuid/DATA_HDD_UUID";
    fsType = "ext4";
    options = [ "defaults" "noatime" ];
  };

  # Off-site backup drive — deliberately NOT always connected (it lives
  # away from the house most of the time and gets plugged in to sync).
  # `noauto` + automount means the system boots fine with it unplugged,
  # and `nofail` means a missing drive never blocks boot. See
  # docs/backups.md for the full rotation procedure.
  fileSystems."/mnt/backup-usb" = {
    device = "/dev/disk/by-uuid/BACKUP_USB_UUID";
    fsType = "ext4";
    options = [ "nofail" "noauto" "x-systemd.automount" "x-systemd.idle-timeout=60" "noatime" ];
  };

  # Swap: zram instead of a disk partition. Simpler (no partition to get
  # wrong at install time), and this server's workloads don't need real
  # disk-backed swap for occasional overflow.
  zramSwap = {
    enable = true;
    memoryPercent = 50;
  };

  # --- /data layout --------------------------------------------------------
  # /data/
  #   nextcloud/        Nextcloud data directory (services.nextcloud.datadir)
  #   media/             Jellyfin's media library (movies/, tv/, music/ — you populate this)
  #   jellyfin/          Jellyfin's own config/metadata/cache (services.jellyfin.dataDir)
  #   immich/upload/     Immich's photo/video library (container bind mount)
  #   immich/postgres/   Immich's own Postgres data (container bind mount)
  #   vaultwarden/       Vaultwarden's sqlite db + attachments
  #   syncthing/         Syncthing's synced folders + index database
  #   forgejo/           Forgejo repos + state (services.forgejo.stateDir)
  #   postgresql/        Shared PostgreSQL cluster data (Nextcloud + Forgejo databases)
  #   backup-staging/    Transient pg_dump output, written fresh before each backup run
  #
  # Each service module sets its data-directory option to point in here
  # rather than the nixpkgs default of /var/lib/<name>, so a stock
  # hardware-configuration.nix with a small root filesystem never fills up,
  # and a single `restic backup /data` (with per-app excludes documented in
  # docs/backups.md) covers everything that matters.
  systemd.tmpfiles.rules = [
    "d /data 0755 root root -"
    "d /data/nextcloud 0750 nextcloud nextcloud -"
    "d /data/media 0755 jellyfin jellyfin -"
    "d /data/jellyfin 0750 jellyfin jellyfin -"
    "d /data/immich 0750 root root -"
    "d /data/immich/upload 0750 immich immich -"
    "d /data/immich/postgres 0750 immich immich -"
    "d /data/vaultwarden 0750 vaultwarden vaultwarden -"
    "d /data/syncthing 0750 syncthing syncthing -"
    "d /data/forgejo 0750 forgejo forgejo -"
    "d /data/postgresql 0750 postgres postgres -"
    "d /data/uptime-kuma 0750 uptime-kuma uptime-kuma -"
    "d /data/backup-staging 0700 root root -"
  ];
}
