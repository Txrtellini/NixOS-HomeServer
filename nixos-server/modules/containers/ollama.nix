{ config, lib, pkgs, ... }:

# OPTIONAL WORKLOAD — not imported by modules/containers/default.nix.
# The core server must boot and run every other service with this file
# entirely absent. To enable: add "./ollama.nix" to the imports list in
# modules/containers/default.nix.
#
# Uses the native NixOS module rather than a container — it's mature and
# gives you clean GPU-passthrough options if you ever add a GPU.
{
  services.ollama = {
    enable = true;
    host = "127.0.0.1";
    port = 11434;
    # acceleration = "cuda"; # uncomment if/when you have an NVIDIA GPU passed through
  };
}
