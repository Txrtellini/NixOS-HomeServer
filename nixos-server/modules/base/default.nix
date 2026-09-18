{ config, lib, pkgs, inputs, ... }:

{
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
    trusted-users = [ "root" "admin" ];
  };

  # Garbage-collect old generations automatically so /nix/store doesn't
  # grow unbounded. This only removes store paths, never Git history or
  # application data — fully safe and reversible (you keep the last 14
  # days of generations, configurable in docs/upgrades.md).
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # NixOS updates itself only via `nixos-rebuild` from this flake — never
  # automatically. See docs/upgrades.md for the full upgrade procedure.
  system.autoUpgrade.enable = false;

  time.timeZone = "YOUR_TIMEZONE"; # e.g. "Europe/Berlin"
  i18n.defaultLocale = "en_US.UTF-8";

  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    dig
    lsof
    smartmontools
    tree
    ncdu
  ];

  # Keep the system minimal and predictable.
  documentation.nixos.enable = false;
  environment.enableAllTerminfo = false;

  nixpkgs.config.allowUnfree = false; # flip to true only if a specific package needs it
}
