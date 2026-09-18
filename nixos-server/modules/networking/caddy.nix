{ config, lib, pkgs, ... }:

{
  # Caddy fronts every web app behind one place: TLS termination, one
  # config style, one log location. Since there's no public domain (this
  # server is WireGuard/LAN-only, per your requirements), Caddy issues
  # its own locally-trusted certificate authority ("tls internal") rather
  # than talking to Let's Encrypt. Install that CA once per client device
  # so browsers stop warning about it — see docs/networking.md for the
  # one-time steps (`caddy trust` output / copying
  # /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt).
  services.caddy = {
    enable = true;

    virtualHosts."nextcloud.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:8081
    '';

    virtualHosts."jellyfin.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:8096
    '';

    virtualHosts."immich.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:2283
    '';

    virtualHosts."vault.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:8000
    '';

    virtualHosts."sync.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:8384
    '';

    virtualHosts."git.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:3001
    '';

    virtualHosts."grafana.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:3000
    '';

    virtualHosts."uptime.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:3002
    '';

    virtualHosts."adguard.srv.home".extraConfig = ''
      tls internal
      reverse_proxy 127.0.0.1:3033
    '';
  };

  # Caddy binds 80/443 — give it the capability instead of running as root.
  systemd.services.caddy.serviceConfig.AmbientCapabilities = [ "CAP_NET_BIND_SERVICE" ];
}
