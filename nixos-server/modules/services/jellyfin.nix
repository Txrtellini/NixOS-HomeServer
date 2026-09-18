{ config, lib, pkgs, ... }:

{
  services.jellyfin = {
    enable = true;
    user = "jellyfin";
    group = "jellyfin";
    dataDir = "/data/jellyfin";
  };

  # Native module, not a container: it's mature, well-integrated with
  # NixOS's hardware-acceleration groups (video/render), and there's no
  # upstream reason to isolate it in a container on this box.
  #
  # If your CPU/GPU supports hardware transcoding and you want to use it,
  # uncomment and adjust:
  # users.users.jellyfin.extraGroups = [ "video" "render" ];
  # hardware.graphics.enable = true;

  systemd.services.jellyfin.serviceConfig.Restart = lib.mkDefault "on-failure";

  environment.systemPackages = [ pkgs.jellyfin-ffmpeg ];
}
