# Upgrades

Nothing upgrades itself automatically (`system.autoUpgrade.enable =
false`, explicitly). Every upgrade is a deliberate, reviewed action you
take from the repository.

## Routine system upgrade

```bash
cd /etc/nixos-server   # or wherever you keep the clone

# 1. Update flake inputs (nixpkgs, sops-nix)
nix flake update

# 2. Inspect exactly what changed before building anything
git diff flake.lock
nix flake metadata   # sanity-check the resolved input revisions

# 3. Build without activating, so a bad build never touches the running system
sudo nixos-rebuild build --flake .#server

# 4. Optional: dry-activate to see what would change without committing to it
sudo nixos-rebuild dry-activate --flake .#server

# 5. Activate
sudo nixos-rebuild switch --flake .#server

# 6. Commit the updated lockfile
git add flake.lock
git commit -m "Update flake inputs"
git push
```

If anything looks wrong after `switch` — a service won't start, a page
won't load — roll back immediately:

```bash
sudo nixos-rebuild switch --rollback
```

## How NixOS generations and rollback work

Every `nixos-rebuild switch` creates a new **generation** — a complete,
independent copy of the system configuration registered as a boot
entry. Older generations aren't deleted until garbage collection
removes them (`modules/base/default.nix` keeps 14 days by default).
This means:

- `sudo nixos-rebuild switch --rollback` immediately re-activates the
  previous generation without reboot, for most changes.
- If the system won't boot at all (rare, but possible with e.g. a bad
  kernel/bootloader change), the boot menu (systemd-boot) lists every
  retained generation — pick an older one at boot time, no rescue media
  needed.
- `nix-env --list-generations --profile /nix/var/nix/profiles/system`
  shows the full history.

## Application container image upgrades

Immich, Uptime Kuma, and the optional Ollama/Open WebUI containers are
pinned to explicit version tags (never `:latest`) in
`modules/containers/*.nix`. Bumping one is a two-line diff:

```nix
immichVersion = "v1.136.0"; # was v1.135.3
```

Check the project's release notes first — Immich in particular
sometimes requires the Postgres image to move in lockstep (the pinned
`postgresImage` in the same file). Build and switch as above; roll back
the same way if the new version misbehaves.

## Nextcloud major version upgrades

Nextcloud enforces sequential major-version upgrades (can't skip a
major version). Bump `services.nextcloud.package` one major version at
a time (`pkgs.nextcloud29` → `pkgs.nextcloud30`, etc.), rebuild, let it
run its upgrade routine, confirm it's healthy, then repeat for the next
version if you need to go further. Don't jump multiple majors in one
change.

## What "safe" means here

- Nothing activates without you running `nixos-rebuild switch`
  yourself.
- Every activation is reviewable beforehand (`build` +
  `dry-activate` before `switch`).
- Every activation is instantly reversible (`--rollback` or the boot
  menu).
- The upgrade procedure is entirely `nix`/`git` commands run from this
  repository — no bespoke upgrade script that could itself rot or
  disappear.
