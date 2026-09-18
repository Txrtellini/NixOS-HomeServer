{ config, lib, pkgs, ... }:

{
  sops.secrets."nextcloud/admin-password" = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "nextcloud";
    mode = "0400";
  };
  sops.secrets."nextcloud/db-password" = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "nextcloud";
    mode = "0400";
  };

  services.nextcloud = {
    enable = true;
    package = pkgs.nextcloud29; # pin explicitly — see docs/upgrades.md before bumping this
    hostName = "nextcloud.srv.home";
    datadir = "/data/nextcloud";

    database.createLocally = false; # we point it at the shared cluster below
    config = {
      dbtype = "pgsql";
      dbhost = "/run/postgresql";
      dbname = "nextcloud";
      dbuser = "nextcloud";
      dbpassFile = config.sops.secrets."nextcloud/db-password".path;
      adminuser = "admin";
      adminpassFile = config.sops.secrets."nextcloud/admin-password".path;
    };

    settings = {
      overwriteprotocol = "https";
      trusted_domains = [ "nextcloud.srv.home" ];
      # Loopback-only origin — Caddy is the only thing that talks to this.
      trusted_proxies = [ "127.0.0.1" ];
    };

    maxUploadSize = "4G";
    configureRedis = true; # local Redis socket for file-locking/caching, no network exposure

    autoUpdateApps.enable = false; # app updates go through your reviewed nixos-rebuild, not silently
  };

  # The Nextcloud module manages its own nginx vhost. Pin it to loopback
  # only — Caddy (modules/networking/caddy.nix) is the thing the network
  # actually talks to, and it reverse-proxies to this port.
  services.nginx.virtualHosts."nextcloud.srv.home" = {
    listen = [{ addr = "127.0.0.1"; port = 8081; }];
    forceSSL = lib.mkForce false;
    enableACME = lib.mkForce false;
  };

  systemd.services.nextcloud-setup.after = [ "postgresql.service" ];
  systemd.services.phpfpm-nextcloud.serviceConfig.Restart = lib.mkDefault "on-failure";
}
