{ config, lib, pkgs, ... }:

{
  imports = [
    ./immich.nix
    ./uptime-kuma.nix
    # ./ollama.nix       # optional — see modules/containers/ollama.nix
    # ./open-webui.nix   # optional — see modules/containers/open-webui.nix
  ];
}
