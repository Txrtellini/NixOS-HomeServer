{ config, lib, pkgs, ... }:

# OPTIONAL WORKLOAD — not imported by modules/containers/default.nix.
# Requires ./ollama.nix to also be enabled. To turn both on, add
# "./ollama.nix" and "./open-webui.nix" to modules/containers/default.nix,
# and add a Caddy vhost + AdGuard rewrite for "webui.srv.home" if you want
# it reachable the same way as the other apps.

let
  openWebuiVersion = "v0.4.8"; # pinned -- check releases before bumping
in
{
  virtualisation.oci-containers.containers.open-webui = {
    image = "ghcr.io/open-webui/open-webui:${openWebuiVersion}";
    environment = {
      OLLAMA_BASE_URL = "http://host.containers.internal:11434";
    };
    volumes = [ "/data/open-webui:/app/backend/data" ];
    ports = [ "127.0.0.1:8090:8080" ];
    extraOptions = [ "--add-host=host.containers.internal:host-gateway" ];
  };

  systemd.services."podman-open-webui".serviceConfig.Restart = lib.mkDefault "on-failure";
}
