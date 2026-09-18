{ config, lib, pkgs, ... }:

{
  services.adguardhome = {
    enable = true;
    # We manage the firewall ourselves in modules/networking/default.nix
    # (port 53 on lan + wg0 only) — don't let the module punch its own
    # holes.
    openFirewall = false;

    # Web admin UI. Reachable only on the LAN and WireGuard interfaces
    # (see firewall config) — never expose this publicly.
    host = "0.0.0.0";
    port = 3033;

    mutableSettings = true; # allow filter-list edits etc. via the UI
    settings = {
      dns = {
        bootstrap_dns = [ "9.9.9.9" "149.112.112.112" ];
        upstream_dns = [ "9.9.9.9" "149.112.112.112" ]; # Quad9; swap for your preferred resolver
        rewrites = [
          # Internal-only hostnames for every proxied app. AdGuard Home
          # answers these for LAN clients AND for WireGuard clients (the
          # WireGuard peer config pushes this server as DNS — see
          # modules/networking/wireguard.nix). Caddy (modules/networking/
          # caddy.nix) terminates TLS for each of these names.
          { domain = "nextcloud.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
          { domain = "jellyfin.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
          { domain = "immich.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
          { domain = "vault.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
          { domain = "sync.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
          { domain = "git.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
          { domain = "grafana.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
          { domain = "uptime.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
          { domain = "adguard.srv.home"; answer = "YOUR_SERVER_LAN_IP"; }
        ];
      };
      filtering = {
        protection_enabled = true;
        filtering_enabled = true;
      };
    };
  };

  # First boot: AdGuard Home needs an admin username/password set once
  # through its web UI setup wizard (http://YOUR_SERVER_LAN_IP:3033) —
  # this isn't meaningfully declarable without hand-generating a bcrypt
  # hash, and the wizard is a one-time, five-second step. Document the
  # password in your password manager, not in Git.
}
