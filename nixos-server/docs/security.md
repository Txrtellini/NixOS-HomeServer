# Security

## Users and access

- One normal administrative user (`admin`), in the `wheel` group for
  `sudo`. SSH-key authentication only — password login is disabled for
  every account, including `admin`, via `hashedPassword = "!"`.
- `root` cannot log in at all, locally or over SSH. Everything
  privileged goes through `sudo` from `admin`, which means every
  privileged action is tied to an SSH-key-authenticated session and
  shows up in `sudo`'s logs.
- `users.mutableUsers = false` — accounts, groups, and SSH keys are
  entirely defined in this repository. There's no `useradd` drift to
  reconcile years from now.

## Podman, not Docker

Docker's daemon runs as root and listens on a socket
(`/var/run/docker.sock`); membership in the `docker` group is
functionally equivalent to passwordless root, because anyone who can
talk to that socket can start a container with `-v /:/host` and write
to the host filesystem as root. Nothing in this deployment needs that.

Podman (used here in rootless mode) has no such daemon — each user's
containers run as that user's own (unprivileged) processes, using user
namespaces to remap container UID 0 to an unprivileged host UID.
There's no group to grant that would hand out root-equivalent access,
so none is granted, and no user on this box is added to any
container-management group. If a future service genuinely requires
rootful Podman (some hardware-passthrough cases do), treat that
decision exactly like handing out root access — document why, and
prefer scoping it to a dedicated system user rather than an
interactive login.

This is also why Docker isn't installed "just in case" — every
containerized service here (Immich, Uptime Kuma) runs fine under
rootless Podman, so there's no capability gap to justify the extra
daemon and its privilege model.

## SSH and network exposure

SSH is firewalled to the LAN and WireGuard interfaces only — see
`docs/networking.md` for the full port table. `PasswordAuthentication`
and `KbdInteractiveAuthentication` are off; only key-based auth is
accepted. `fail2ban` is enabled as a second layer in case a LAN device
is ever compromised or a future firewall change is made in error — it's
not load-bearing given SSH isn't internet-facing, but it's cheap and
harmless.

## Secrets

Every password, token, and private key lives in `secrets/secrets.yaml`,
encrypted with sops against an age key that itself never enters Git.
See `secrets/README.md` for the full workflow. Each secret is decrypted
by sops-nix at system activation to a root-owned, mode-0400 file
readable only by the specific service user that needs it — application
config in this repo references `config.sops.secrets."...".path`, never
a literal value.

## Hardening posture, and what's deliberately not done

This configuration hardens the things with a clear payoff and a
low/understood cost: no password auth anywhere, no root login, a
default-deny firewall with every open port documented, least-privilege
container access, secrets out of Git. It deliberately does **not** pile
on kernel-hardening sysctls, AppArmor/SELinux profiles per service, or
aggressive `systemd`-level sandboxing (`ProtectSystem=strict`,
`NoNewPrivileges`, seccomp filters, etc.) across every unit — each of
those is a legitimate hardening technique, but adding them wholesale,
service by service, without testing each one against its actual
service is exactly the kind of "incomprehensible collection of
security tweaks" you asked to avoid, and a wrong sandboxing option is a
realistic way to turn "reliable" into "mysteriously broken after an
update." If you want to harden a specific service further later, do it
one service at a time, verify it still works, and keep the reasoning
in a comment next to the option — the same discipline used everywhere
else in this repo.

## Why Kubernetes is excluded

Kubernetes solves problems this deployment doesn't have: scheduling
workloads across multiple nodes, rolling out changes to many replicas
without downtime, and abstracting over heterogeneous hardware. On one
box, "schedule the pod somewhere" has exactly one possible answer, so a
scheduler adds no value. What it would add is a whole second layer of
systems to keep reliable, reproducible, secure, and recoverable — etcd
(itself needing backup and disaster recovery), a control plane, a CNI
plugin, likely an ingress controller — none of which do anything a
plain `systemd` unit doesn't already do more simply for a single host.
It directly works against nearly every stated priority (reliability,
simplicity, avoiding configuration debt) for zero corresponding
benefit at this scale.
