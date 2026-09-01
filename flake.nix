{
  description = "Wintix - personal declarative NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      disko,
      self,
      ...
    }:
    let
      system = "x86_64-linux";
      unstablePkgs = import nixpkgs-unstable { inherit system; };
      storageConfig =
        mode:
        { device, ... }:
        {
          disko.devices.disk = import ./modules/storage-layout.nix {
            inherit device mode;
          };
        };
    in
    {
      nixosConfigurations.desktop = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit unstablePkgs; };
        modules = [
          disko.nixosModules.disko
          ./hosts/desktop/default.nix
          home-manager.nixosModules.home-manager
        ];
      };

      nixosModules.wintix-storage = ./modules/storage.nix;

      # These functions are evaluated by Disko with --argstr at installer time.
      # No target device is embedded in the reusable provisioning interface.
      diskoConfigurations = {
        wintix-whole-disk = storageConfig "whole-disk";
        wintix-selected-partition = storageConfig "selected-partition";
      };

      packages.${system} = {
        disko = disko.packages.${system}.disko;
        installer = nixpkgs.legacyPackages.${system}.writeShellApplication {
          name = "wintix-install";
          runtimeInputs = with nixpkgs.legacyPackages.${system}; [
            bash
            coreutils
            cryptsetup
            curl
            findutils
            git
            gnugrep
            gnused
            gawk
            gptfdisk
            jq
            nix
            nixos-install-tools
            openssl
            util-linux
            gum
          ];
          text = ''exec ${./installer/install.sh} "$@"'';
        };
        default = disko.packages.${system}.disko;
      };

      apps.${system}.install = {
        type = "app";
        program = "${self.packages.${system}.installer}/bin/wintix-install";
      };
    };
}
