{ config, lib, pkgs, ... }:

let
  # Pin every image to an explicit version — never ":latest"/":release".
  # Check https://github.com/immich-app/immich/releases for the current
  # stable tag before your first deploy and update this (and re-check
  # before every upgrade — see docs/upgrades.md).
  immichVersion = "v1.135.3"; # EXAMPLE — verify and replace before deploying
  postgresImage = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0";
  valkeyImage = "docker.io/valkey/valkey:9";
in
{
  sops.secrets."immich/db-password" = {
    sopsFile = ../../secrets/secrets.yaml;
    mode = "0400";
  };

  virtualisation.podman.enable = true;
  virtualisation.oci-containers.backend = "podman";

  # Immich's server, ML service, Postgres and Redis/Valkey need to reach
  # each other by name — give them their own bridge network rather than
  # publishing every internal port to the host.
  systemd.services.podman-network-immich = {
    description = "Create the podman network for Immich";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
    script = "${pkgs.podman}/bin/podman network create --ignore immich";
  };

  virtualisation.oci-containers.containers = {
    immich-postgres = {
      image = postgresImage;
      environment = {
        POSTGRES_USER = "immich";
        POSTGRES_DB = "immich";
      };
      environmentFiles = [ config.sops.secrets."immich/db-password".path ]; # provides POSTGRES_PASSWORD
      volumes = [ "/data/immich/postgres:/var/lib/postgresql/data" ];
      extraOptions = [ "--network=immich" "--network-alias=immich-postgres" ];
    };

    immich-redis = {
      image = valkeyImage;
      extraOptions = [ "--network=immich" "--network-alias=immich-redis" ];
    };

    immich-server = {
      image = "ghcr.io/immich-app/immich-server:${immichVersion}";
      environment = {
        DB_HOSTNAME = "immich-postgres";
        DB_USERNAME = "immich";
        DB_DATABASE_NAME = "immich";
        REDIS_HOSTNAME = "immich-redis";
        UPLOAD_LOCATION = "/usr/src/app/upload";
        IMMICH_MACHINE_LEARNING_URL = "http://immich-ml:3003";
      };
      environmentFiles = [ config.sops.secrets."immich/db-password".path ]; # provides DB_PASSWORD (same value as POSTGRES_PASSWORD)
      volumes = [ "/data/immich/upload:/usr/src/app/upload" ];
      ports = [ "127.0.0.1:2283:2283" ]; # loopback only — Caddy proxies this
      extraOptions = [ "--network=immich" "--network-alias=immich-server" ];
      dependsOn = [ "immich-postgres" "immich-redis" ];
    };

    immich-ml = {
      image = "ghcr.io/immich-app/immich-machine-learning:${immichVersion}";
      volumes = [ "immich-model-cache:/cache" ];
      extraOptions = [ "--network=immich" "--network-alias=immich-ml" ];
    };
  };

  systemd.services."podman-immich-postgres".after = [ "podman-network-immich.service" ];
  systemd.services."podman-immich-redis".after = [ "podman-network-immich.service" ];
  systemd.services."podman-immich-ml".after = [ "podman-network-immich.service" ];
  systemd.services."podman-immich-server".after = [ "podman-network-immich.service" ];

  # Restart containers on failure, and make sure they come back after a
  # host reboot without manual intervention.
  systemd.services."podman-immich-postgres".serviceConfig.Restart = lib.mkDefault "on-failure";
  systemd.services."podman-immich-redis".serviceConfig.Restart = lib.mkDefault "on-failure";
  systemd.services."podman-immich-server".serviceConfig.Restart = lib.mkDefault "on-failure";
  systemd.services."podman-immich-ml".serviceConfig.Restart = lib.mkDefault "on-failure";
}
