{ config, lib, pkgs, ... }:

{
  imports = [
    ./postgresql.nix
    ./nextcloud.nix
    ./vaultwarden.nix
    ./syncthing.nix
    ./forgejo.nix
    ./jellyfin.nix
  ];
}
