{ config, lib, pkgs, ... }:

let
  lanInterface = "YOUR_LAN_INTERFACE"; # e.g. "eno1" — run `ip link` to find it
  wgInterface = "wg0";
in
{
  imports = [
    ./wireguard.nix
    ./caddy.nix
    ./adguard.nix
  ];

  networking.useDHCP = false;

  # Static LAN IP is strongly preferred for a server — set a DHCP
  # reservation for this MAC on your router AND pin it here so the two
  # never disagree.
  networking.interfaces.${lanInterface}.ipv4.addresses = [{
    address = "YOUR_SERVER_LAN_IP"; # e.g. "192.168.1.10"
    prefixLength = 24; # matches YOUR_LAN_SUBNET, e.g. 192.168.1.0/24
  }];
  networking.defaultGateway = "YOUR_ROUTER_IP"; # e.g. "192.168.1.1"
  networking.nameservers = [ "127.0.0.1" ]; # the server resolves via its own AdGuard Home

  # --- Firewall: default-deny, explicit allow per interface --------------
  #
  # Every opened port is documented here. Nothing is opened on any
  # interface other than the LAN and the WireGuard tunnel — this box has
  # no interface directly facing the public internet; only your router's
  # forwarded WireGuard UDP port reaches it, and that's handled by the
  # router, not this firewall.
  networking.firewall = {
    enable = true;
    # No ports open by default on interfaces not listed below.
    interfaces.${lanInterface}.allowedTCPPorts = [
      22    # SSH — trusted physical LAN only
      53    # AdGuard Home DNS (TCP fallback)
      443   # Caddy reverse proxy (TLS) to all web apps
      2222  # Forgejo's own SSH (git clone/push over SSH)
      22000 # Syncthing sync protocol
    ];
    interfaces.${lanInterface}.allowedUDPPorts = [
      53    # AdGuard Home DNS
      21027 # Syncthing local peer discovery (LAN broadcast only)
      22000 # Syncthing sync protocol (QUIC)
    ];

    interfaces.${wgInterface}.allowedTCPPorts = [
      22    # SSH for remote administration
      53    # DNS for WireGuard road-warrior clients
      443   # Caddy reverse proxy — same apps, reachable while away from home
      2222  # Forgejo SSH
      22000 # Syncthing sync protocol, so a phone on WireGuard can still sync
    ];
    interfaces.${wgInterface}.allowedUDPPorts = [
      53
      22000
    ];

    # The WireGuard UDP listen port must be reachable on whatever
    # interface faces your router (the one with YOUR_SERVER_LAN_IP),
    # since the router forwards it there.
    interfaces.${lanInterface}.allowedUDPPortRanges = [
      { from = 51820; to = 51820; }
    ];
  };
}
