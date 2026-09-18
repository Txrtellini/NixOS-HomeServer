# Installation

## 1. Partition the disks

Boot the NixOS installer. Example layout matching
`hosts/server/hardware-configuration.nix`'s expectations (adjust device
names to your actual `/dev/sdX` or `/dev/nvmeXn1`):

```bash
# SSD (256GB) — system disk
parted /dev/YOUR_SSD -- mklabel gpt
parted /dev/YOUR_SSD -- mkpart ESP fat32 1MiB 513MiB
parted /dev/YOUR_SSD -- set 1 esp on
parted /dev/YOUR_SSD -- mkpart primary 513MiB 100%

mkfs.fat -F32 -n boot /dev/YOUR_SSD1
pvcreate /dev/YOUR_SSD2
vgcreate system /dev/YOUR_SSD2
lvcreate -L 200G -n root system
mkfs.ext4 -L nixos / dev/system/root

# HDD (4TB) — application data
parted /dev/YOUR_HDD -- mklabel gpt
parted /dev/YOUR_HDD -- mkpart primary 1MiB 100%
mkfs.ext4 -L data /dev/YOUR_HDD1

# Mount for install
mount /dev/system/root /mnt
mkdir -p /mnt/boot /mnt/data
mount /dev/YOUR_SSD1 /mnt/boot
mount /dev/YOUR_HDD1 /mnt/data
```

## 2. Generate hardware config, install a minimal system

```bash
nixos-generate-config --root /mnt
nixos-install   # uses the generated config for a minimal first boot
reboot
```

## 3. Bring the flake onto the machine

```bash
sudo -i
nix-shell -p git   # if git isn't already present
git clone <your-remote-url> /etc/nixos-server
cd /etc/nixos-server
```

Copy the real `/etc/nixos/hardware-configuration.nix` generated in step
2 over `hosts/server/hardware-configuration.nix` in the repo.

## 4. Fill in every placeholder

```bash
grep -rn "YOUR_" --include='*.nix' .
```

Work through each one: hostname, timezone, LAN interface name and IP,
router IP, disk UUIDs (`blkid`), your SSH public key, WireGuard server
key (`wg genkey | tee server-private.key | wg pubkey > server-public.key`
— put the private key in secrets, not in Git), and one WireGuard peer
block per client device.

## 5. Set up secrets

Follow `secrets/README.md` in full: generate the age key, install it at
`/var/lib/sops-nix/key.txt`, create and encrypt `secrets/secrets.yaml`
from the `.example` template.

## 6. Build and activate

```bash
sudo nixos-rebuild switch --flake .#server
```

## 7. One-time interactive setup steps

A few things are genuinely one-time and interactive rather than
declarative — doing them via Nix would mean hand-generating password
hashes or API tokens for no real benefit:

- **AdGuard Home**: visit `http://YOUR_SERVER_LAN_IP:3033` once, complete
  the setup wizard (admin username/password — store it in your password
  manager).
- **Vaultwarden**: temporarily set `SIGNUPS_ALLOWED = true` in
  `modules/services/vaultwarden.nix`, rebuild, create your account at
  `https://vault.srv.home`, then set it back to `false` and rebuild
  again.
- **Forgejo**: create your admin account with
  `forgejo admin user create --admin --username you --email you@example.com`.
- **Syncthing**: pair devices through the GUI at `https://sync.srv.home`.
- **Caddy's internal CA**: install its root certificate on each of your
  devices — see `docs/networking.md`.

## Validation

Run these after any change, before considering a rebuild "done":

```bash
# Flake and evaluation sanity
nix flake check .

# Build without activating — catches evaluation and build errors safely
sudo nixos-rebuild build --flake .#server

# Firewall — confirm only the documented ports are open
sudo nft list ruleset | less
# or
sudo iptables -L -n -v

# Services
systemctl --failed              # should be empty
systemctl status nextcloud jellyfin vaultwarden syncthing forgejo \
  caddy adguardhome prometheus grafana alertmanager postgresql

# Containers
podman ps
podman logs immich-server --tail 50

# Storage
df -h /              # SSD headroom
df -h /data           # HDD headroom
mountpoint /mnt/backup-usb   # only meaningful with the drive plugged in

# Backups
sudo systemctl start restic-backup.service   # run one on demand
sudo journalctl -u restic-backup -e
curl -s http://127.0.0.1:9100/metrics | grep backup_

# DNS
dig @YOUR_SERVER_LAN_IP nextcloud.srv.home

# TLS
curl -kv https://nextcloud.srv.home 2>&1 | grep -A2 "subject:"
```
