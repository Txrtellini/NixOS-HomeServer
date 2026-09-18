{ config, lib, pkgs, ... }:

let
  uptimeKumaVersion = "1.23.16"; # pinned — check https://github.com/louislam/uptime-kuma/releases before bumping
in
{
  virtualisation.oci-containers.containers.uptime-kuma = {
    image = "louislam/uptime-kuma:${uptimeKumaVersion}";
    volumes = [ "/data/uptime-kuma:/app/data" ];
    ports = [ "127.0.0.1:3002:3001" ]; # loopback only — Caddy proxies this
  };

  systemd.services."podman-uptime-kuma".serviceConfig.Restart = lib.mkDefault "on-failure";
}
