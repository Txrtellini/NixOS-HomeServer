{ config, lib, pkgs, ... }:

{
  # Fully declarative user accounts — no drift between what's in Git and
  # what's actually on the box.
  users.mutableUsers = false;

  users.users.admin = {
    isNormalUser = true;
    extraGroups = [ "wheel" ]; # sudo access. Deliberately NOT in "podman" —
      # see the comment on container access below before ever adding it.
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... YOUR_SSH_PUBLIC_KEY"
    ];
    # No password login at all — SSH key only, everywhere, always.
    hashedPassword = "!";
  };

  # Root cannot log in at all — not even with a key. Use `sudo` from the
  # admin account for anything that needs root.
  users.users.root.hashedPassword = "!";

  security.sudo.wheelNeedsPassword = false; # SSH-key-authenticated session already proves identity;
    # flip to `true` if you want a second factor at sudo time too.

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # SSH is only reachable via the LAN and WireGuard interfaces (see
  # modules/networking/default.nix) — it's never internet-facing — but
  # fail2ban is cheap insurance against a compromised LAN device or a
  # misconfigured firewall change down the line.
  services.fail2ban.enable = true;

  # --- Container privilege boundary ---------------------------------------
  # Podman is used instead of Docker specifically because rootless Podman
  # has no long-lived root-owned daemon socket — membership in a
  # container-management group (Docker's "docker" group, or Podman's
  # equivalent for *rootful* Podman) is equivalent to root on the host,
  # because anyone in that group can bind-mount / into a container and
  # write to it as root. This config runs Podman rootless (see
  # modules/containers), so no user needs to be in a privileged group to
  # manage these containers, and none are added to one. If you ever add
  # a container that genuinely requires rootful Podman, treat granting
  # that access the same as granting root and document why.

  # System users for containerized services that don't ship their own
  # NixOS user (native services like Nextcloud/Vaultwarden/etc. create
  # their own users automatically). Fixed UIDs keep bind-mount ownership
  # under /data stable across rebuilds.
  users.groups.immich = { gid = 986; };
  users.users.immich = {
    isSystemUser = true;
    group = "immich";
    uid = 986;
  };

  users.groups.uptime-kuma = { gid = 987; };
  users.users.uptime-kuma = {
    isSystemUser = true;
    group = "uptime-kuma";
    uid = 987;
  };
}
