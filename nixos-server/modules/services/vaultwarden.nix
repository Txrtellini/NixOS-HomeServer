{ config, lib, pkgs, ... }:

{
  sops.secrets."vaultwarden/env" = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "vaultwarden";
    mode = "0400";
  };

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite"; # fine at this scale; avoids a third Postgres database to manage
    environmentFile = config.sops.secrets."vaultwarden/env".path; # ADMIN_TOKEN=... in there, see secrets/README.md
    config = {
      DOMAIN = "https://vault.srv.home";
      SIGNUPS_ALLOWED = false; # flip true only briefly, to create your own account, then back off
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8000;
      DATA_FOLDER = "/data/vaultwarden";
      WEBSOCKET_ENABLED = true;
    };
  };

  systemd.services.vaultwarden.serviceConfig.Restart = lib.mkDefault "on-failure";
}
