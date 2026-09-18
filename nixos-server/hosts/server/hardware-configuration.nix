# PLACEHOLDER — this file is intentionally hardware-specific.
#
# Do NOT hand-write this. On the target machine, after booting the NixOS
# installer and partitioning/formatting disks, run:
#
#   nixos-generate-config --root /mnt
#
# then copy the generated /mnt/etc/nixos/hardware-configuration.nix over
# this file verbatim. It contains your real disk UUIDs, filesystem types,
# kernel modules for your specific hardware, and CPU microcode settings.
#
# The partition/mount layout this configuration expects (set up manually
# with `parted`/`mkfs` before running nixos-generate-config, or adjust the
# generated file to match):
#
#   /dev/YOUR_SSD  (256GB SSD — system disk)
#     ├─ 512MiB  EFI System Partition  -> /boot   (vfat)
#     └─ rest    LVM PV -> VG "system" -> LV "root" -> /  (ext4)
#
#   /dev/YOUR_HDD  (4TB HDD — application data)
#     └─ 1 partition, ext4, -> /data
#
#   /dev/YOUR_BACKUP_USB  (external drive — NOT always connected)
#     └─ 1 partition, ext4, -> /mnt/backup-usb (mounted on demand,
#        see modules/storage/default.nix)
#
# This repo's modules/storage/default.nix references /data and
# /mnt/backup-usb by UUID placeholders (DATA_HDD_UUID, BACKUP_USB_UUID).
# Fill those in from `blkid` output once the real hardware-configuration.nix
# is in place.

{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # --- Everything below is a stand-in until you replace this file. ---
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ]; # or "kvm-amd" — depends on your CPU
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/YOUR_ROOT_LABEL";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/YOUR_BOOT_LABEL";
    fsType = "vfat";
  };

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true; # or .amd.updateMicrocode
}
