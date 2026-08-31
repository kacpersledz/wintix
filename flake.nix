{
  description = "Wintix - personal declarative NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      unstablePkgs = import nixpkgs-unstable {
        system = "x86_64-linux";
      };
    in
    {
      nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        specialArgs = { inherit unstablePkgs; };
        modules = [ ./hosts/desktop/default.nix ];
      };
    };
}
