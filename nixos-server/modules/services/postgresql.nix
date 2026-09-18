{ config, lib, pkgs, ... }:

{
  # One shared PostgreSQL instance for the native apps that want a real
  # SQL database (Nextcloud, Forgejo). Immich is deliberately NOT here —
  # it needs a specific Postgres build with the pgvecto.rs/pgvector
  # extension matched to its own release, so it keeps its own containerized
  # Postgres (see modules/containers/immich.nix) rather than fighting this
  # cluster's extension set. Two Postgres data directories is a small
  # price for not coupling Immich's upgrade cadence to this cluster's.
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;
    dataDir = "/data/postgresql/16";

    ensureDatabases = [ "nextcloud" "forgejo" ];
    ensureUsers = [
      {
        name = "nextcloud";
        ensureDBOwnership = true;
      }
      {
        name = "forgejo";
        ensureDBOwnership = true;
      }
    ];

    # Local-socket auth only — nothing here listens on TCP, let alone the
    # network. Both Nextcloud and Forgejo connect over the Unix socket.
    authentication = lib.mkForce ''
      local all all peer
    '';
  };

  # Postgres restarts cleanly and automatically on failure; a hard crash
  # of Postgres shouldn't require manual intervention to recover the
  # service (though see docs/disaster-recovery.md for what to do about
  # potential data corruption).
  systemd.services.postgresql.serviceConfig.Restart = lib.mkDefault "on-failure";
}
