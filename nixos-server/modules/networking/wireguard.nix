{ config, lib, pkgs, ... }:

{
  # The server's WireGuard private key is a secret — never in Git.
  # See secrets/README.md. sops-nix decrypts it to a root-only file at
  # activation time and this option just points at that path.
  sops.secrets."wireguard/private-key" = {
    sopsFile = ../../secrets/secrets.yaml;
    mode = "0400";
    owner = "root";
  };

  networking.wireguard.interfaces.wg0 = {
    ips = [ "10.100.0.1/24" ];
    listenPort = 51820;
    privateKeyFile = config.sops.secrets."wireguard/private-key".path;

    # Add one peer block per device (phone, laptop, etc). Generate each
    # client's keypair on the client itself (`wg genkey | tee priv | wg
    # pubkey > pub`) — private keys never need to touch this server.
    peers = [
      {
        # Example client — duplicate this block per device and replace
        # the placeholders. Delete this example before deploying.
        publicKey = "YOUR_CLIENT_1_PUBLIC_KEY";
        allowedIPs = [ "10.100.0.2/32" ];
      }
    ];
  };

  # This box does NOT route WireGuard clients to the rest of your LAN —
  # only to itself. That's intentional: it's the smallest privilege that
  # satisfies "reach the server's services while away from home" without
  # turning this machine into a full VPN gateway for your network. If you
  # later want WireGuard clients to reach other LAN devices too, you'd
  # enable boot.kernel.sysctl."net.ipv4.ip_forward" = 1 and add NAT —
  # deliberately left out for now (smaller attack surface, simpler to
  # reason about).
}
