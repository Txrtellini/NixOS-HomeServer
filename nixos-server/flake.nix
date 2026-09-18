{
  description = "Home server NixOS configuration";

  inputs = {
    # Pinned to a stable NixOS release branch. Before first deploy, check
    # https://status.nixos.org for the current stable release and update
    # this if nixos-24.11 has gone EOL by the time you read this.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";

    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... }@inputs: {
    nixosConfigurations.server = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      modules = [
        sops-nix.nixosModules.sops
        ./hosts/server
      ];
    };
  };
}
