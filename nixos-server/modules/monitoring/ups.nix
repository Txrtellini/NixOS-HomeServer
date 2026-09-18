{ config, lib, pkgs, ... }:

# OPTIONAL — not imported by modules/monitoring/default.nix. You didn't
# specify a UPS, so nothing here assumes one exists. If you get one,
# add "../monitoring/ups.nix" to hosts/server/default.nix's imports and
# fill in the placeholders below.
#
# Uses Network UPS Tools (NUT), which supports most USB/serial UPS
# brands (APC, CyberPower, Eaton, etc.) through one driver interface
# rather than committing to a brand-specific daemon.
{
  power.ups = {
    enable = true;
    ups.homeups = {
      driver = "usbhid-ups"; # works for most USB UPS units; check `ups -h` / NUT hardware compatibility list for yours
      port = "auto";
      description = "Home server UPS";
    };
  };

  # What happens at each stage:
  #  - Short power loss: the UPS runs on battery, NUT logs the event,
  #    nothing else happens — the server keeps running normally.
  #  - Prolonged power loss / low battery: `upsmon` (enabled by
  #    power.ups.enable) triggers a clean `shutdown -h now` before the
  #    battery is exhausted, so the filesystem is unmounted cleanly
  #    instead of losing power mid-write.
  #  - Power returns after a clean shutdown: with the BIOS/UEFI set to
  #    "power on after AC loss" (set this in firmware — it's not a
  #    software setting), the server boots itself back up unattended.
  power.ups.mode = "standalone";
}
