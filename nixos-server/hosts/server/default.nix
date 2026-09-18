{ config, lib, pkgs, inputs, ... }:

{
  imports = [
    ./hardware-configuration.nix

    ../../modules/base
    ../../modules/networking
    ../../modules/storage
    ../../modules/security
    ../../modules/monitoring
    ../../modules/backups
    ../../modules/services
    ../../modules/containers
  ];

  # --- Secrets --------------------------------------------------------------
  # A dedicated age key (NOT derived from the SSH host key) so it stays
  # valid across a full hardware reinstall — the host key changes on
  # reinstall, this file doesn't have to. Generate it once with
  # `age-keygen -o key.txt`, install it at this exact path with 0600
  # permissions, and back it up out-of-band (see secrets/README.md and
  # docs/backups.md — this file is deliberately NOT inside the Restic
  # backup, since it's what decrypts everything else).
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";
  sops.defaultSopsFile = ../../secrets/secrets.yaml;

  # --- Identity -----------------------------------------------------------
  networking.hostName = "YOUR_HOSTNAME"; # e.g. "homeserver"

  # Bootloader: systemd-boot on a UEFI system. If your hardware is legacy
  # BIOS, replace this with boot.loader.grub instead.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 10; # keep last 10 generations bootable
  boot.loader.efi.canTouchEfiVariables = true;

  system.stateVersion = "24.11"; # do not change after install — see docs/upgrades.md
}
