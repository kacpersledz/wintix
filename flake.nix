{
  description = "Wintix - personal declarative NixOS configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      plasma-manager,
      disko,
      sops-nix,
      self,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      unstablePkgs = import nixpkgs-unstable { inherit system; };
      wintixRuntimeInputs = with pkgs; [
        bash
        coreutils
        git
        nix
        nixos-rebuild
      ];
      wintixRebuild = pkgs.writeShellApplication {
        name = "wintix-rebuild";
        runtimeInputs = wintixRuntimeInputs;
        text = builtins.readFile ./commands/wintix-rebuild.sh;
      };
      wintixUpdate = pkgs.writeShellApplication {
        name = "wintix-update";
        runtimeInputs = wintixRuntimeInputs;
        text = builtins.readFile ./commands/wintix-update.sh;
      };
      wintixSecretsBootstrap = pkgs.writeShellApplication {
        name = "wintix-secrets-bootstrap";
        runtimeInputs = with pkgs; [ age coreutils systemd ];
        text = builtins.readFile ./commands/wintix-secrets-bootstrap.sh;
      };
      wintixSecretsEnroll = pkgs.writeShellApplication {
        name = "wintix-secrets-enroll";
        runtimeInputs = with pkgs; [ age coreutils gnugrep openssh sops ];
        text = builtins.readFile ./commands/wintix-secrets-enroll.sh;
      };
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
        specialArgs = {
          inherit self unstablePkgs;
        };
        modules = [
          disko.nixosModules.disko
          ./hosts/desktop/default.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.sharedModules = [
              plasma-manager.homeModules.plasma-manager
              sops-nix.homeManagerModules.sops
            ];
          }
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
        wintix-rebuild = wintixRebuild;
        wintix-update = wintixUpdate;
        wintix-secrets-bootstrap = wintixSecretsBootstrap;
        wintix-secrets-enroll = wintixSecretsEnroll;
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
          # Reference the whole directory so install.sh can source its sibling
          # modules, and invoke it through Bash instead of relying on executable
          # mode bits of a source file copied into the Nix store.
          text = ''exec bash ${./installer}/install.sh "$@"'';
        };
        default = disko.packages.${system}.disko;
      };

      apps.${system}.install = {
        type = "app";
        program = "${self.packages.${system}.installer}/bin/wintix-install";
      };
    };
}
