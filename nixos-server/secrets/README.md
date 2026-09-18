# Secrets

This directory holds `secrets.yaml` — every password/token/key the
configuration needs, encrypted with [sops](https://github.com/getsops/sops)
against an [age](https://github.com/FiloSottile/age) key. The **encrypted**
file is safe to commit; nothing here is readable without the private age
key, which never goes in Git.

## One-time setup (new server)

```bash
# On your admin workstation (or the server itself):
age-keygen -o key.txt
age-keygen -y key.txt          # prints the public key — paste into .sops.yaml

# Install the private key on the server:
sudo mkdir -p /var/lib/sops-nix
sudo cp key.txt /var/lib/sops-nix/key.txt
sudo chmod 600 /var/lib/sops-nix/key.txt

# Back the private key up OUT OF BAND — a password manager entry, a
# printed QR code in a safe, a second encrypted USB stick kept
# separately from the backup drive. If you lose this key with no copy,
# every secret in Git becomes permanently unreadable, even though the
# Restic backup and the Git history are both intact. This is the one
# piece of the whole system that has no automated backup, on purpose —
# see docs/backups.md.
```

## Creating secrets.yaml

```bash
cp secrets/secrets.yaml.example secrets/secrets.yaml
$EDITOR secrets/secrets.yaml       # fill in real values
sops --encrypt --in-place secrets/secrets.yaml
git add secrets/secrets.yaml
```

## Editing secrets later

```bash
sops secrets/secrets.yaml   # decrypts to $EDITOR, re-encrypts on save
```

## Adding a new secret

1. Add the key to `secrets/secrets.yaml.example` (placeholder value) so
   the template stays accurate.
2. `sops secrets/secrets.yaml`, add the real key/value, save.
3. Reference it in the relevant module:
   ```nix
   sops.secrets."myapp/some-secret" = {
     sopsFile = ../../secrets/secrets.yaml;
     owner = "myapp";
     mode = "0400";
   };
   ```
   The decrypted value is available at runtime at
   `config.sops.secrets."myapp/some-secret".path` — never inline the
   value itself into a Nix file.
