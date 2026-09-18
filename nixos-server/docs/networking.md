# Networking

## Topology

- **LAN**: the server has a static IP on your home network.
- **WireGuard**: the only way in from outside your home. Your router
  forwards one UDP port to the server; nothing else is forwarded.
- **No public domain, no ACME, no port 80/443 exposed to the internet.**
  Every app is reached either from the LAN directly, or from anywhere
  via WireGuard first (after which it looks like the LAN to the app).

## Every opened port, and why

| Port | Proto | Interfaces | Purpose |
|---|---|---|---|
| 51820 | UDP | LAN (router forwards this to the server) | WireGuard tunnel endpoint |
| 22 | TCP | LAN, wg0 | SSH administration |
| 53 | TCP+UDP | LAN, wg0 | AdGuard Home DNS, for LAN clients and WireGuard road-warrior clients |
| 443 | TCP | LAN, wg0 | Caddy — fronts every web app with one TLS certificate authority |
| 2222 | TCP | LAN, wg0 | Forgejo's own SSH (git clone/push over SSH, kept off port 22 deliberately so it can't collide with or be confused for host SSH) |
| 22000 | TCP+UDP | LAN, wg0 | Syncthing sync protocol, so a phone on WireGuard can still sync files while you're out |
| 21027 | UDP | LAN only | Syncthing local peer discovery (broadcast — meaningless over a routed WireGuard tunnel, so LAN-only) |

Nothing else is opened, on any interface. In particular, **none of
these are reachable from the public internet directly**: Grafana,
Prometheus, Uptime Kuma, AdGuard Home's admin UI, and Forgejo's admin
panel are all behind Caddy on port 443, which is itself only bound on
the LAN and WireGuard interfaces — there is no interface on this
machine that faces the internet directly at all. The only thing your
router forwards is the WireGuard UDP port, and WireGuard rejects every
packet that isn't cryptographically part of an established tunnel with
a known peer key, so an unauthenticated scan of that port sees nothing.

## LAN-only vs. WireGuard vs. "public"

Given your requirement (reachable while away from home, but only via
WireGuard, no paid domain), the actual breakdown is:

- **Nothing is public.** There is no service in this configuration
  reachable by an unauthenticated client on the open internet.
- **Everything is LAN-or-WireGuard.** Once you're on the LAN *or*
  connected via WireGuard, the two are equivalent from the app's point
  of view — same DNS names, same Caddy certificate, same ports.

If you later decide you do want something public (e.g. sharing a
Nextcloud folder link with someone who doesn't have WireGuard set up),
that's a deliberate, separate decision — it means getting a real domain,
switching that one Caddy vhost to ACME, and opening 443 on the WAN side
of your router to just that one service. Nothing in this config assumes
you'll do that, and nothing breaks if you never do.

## TLS without a public domain

Caddy issues certificates from its own internal certificate authority
(`tls internal` in `modules/networking/caddy.nix`) instead of Let's
Encrypt, since there's no public domain for ACME to validate against.
Browsers will warn about this CA once, on each device, until you trust
it:

```bash
# On the server, after first boot:
sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt
```

Copy that file to each device you use (phone, laptop) and install it as
a trusted root certificate authority. This is a one-time step per
device. Until you do it, the apps still work — browsers just show a
certificate warning you have to click through.

## AdGuard Home's role

AdGuard Home is this network's DNS server (ad/tracker blocking is a
side benefit, not the reason it's here) — it resolves `*.srv.home`
names to the server's LAN IP for both LAN clients and WireGuard peers
(set your WireGuard client's DNS to `10.100.0.1`, the server's
WireGuard address, so `*.srv.home` names resolve correctly while
you're away). Set your router to hand out the server's LAN IP as the
DNS server via DHCP so LAN devices pick this up automatically.
