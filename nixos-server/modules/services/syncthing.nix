{ config, lib, pkgs, ... }:

{
  services.syncthing = {
    enable = true;
    user = "syncthing";
    group = "syncthing";
    dataDir = "/data/syncthing";
    configDir = "/data/syncthing/.config";

    guiAddress = "127.0.0.1:8384"; # Caddy proxies the GUI; never bind this to 0.0.0.0

    # No `declarative.devices`/`declarative.folders` block here on purpose:
    # folder pairing is something you do once, interactively, through the
    # GUI (adding a phone, approving a folder) — encoding it declaratively
    # just means re-typing device IDs into Nix by hand. What matters for
    # reproducibility is that the *database* (device pairings, folder
    # list) lives under /data/syncthing and is covered by Restic, so a
    # full restore brings all of that back without redoing the pairing.
    openDefaultPorts = false; # we open exactly what's needed, explicitly, in modules/networking
  };

  systemd.services.syncthing.serviceConfig.Restart = lib.mkDefault "on-failure";
}
