{ config, lib, pkgs, ... }:

{
  sops.secrets."forgejo/db-password" = {
    sopsFile = ../../secrets/secrets.yaml;
    owner = "forgejo";
    mode = "0400";
  };

  services.forgejo = {
    enable = true;
    stateDir = "/data/forgejo";

    database = {
      type = "postgres";
      host = "/run/postgresql";
      name = "forgejo";
      user = "forgejo";
      passwordFile = config.sops.secrets."forgejo/db-password".path;
    };

    settings = {
      server = {
        DOMAIN = "git.srv.home";
        ROOT_URL = "https://git.srv.home/";
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = 3001;
        START_SSH_SERVER = true;
        SSH_LISTEN_HOST = "0.0.0.0"; # firewall (modules/networking) restricts this to lan+wg0
        SSH_LISTEN_PORT = 2222;
      };
      service.DISABLE_REGISTRATION = true; # you create accounts manually via the admin CLI
      repository.ROOT = "/data/forgejo/repositories";
    };
  };

  systemd.services.forgejo.serviceConfig.Restart = lib.mkDefault "on-failure";
  systemd.services.forgejo.after = [ "postgresql.service" ];
}
