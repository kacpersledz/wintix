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
      unstablePkgs = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
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
        runtimeInputs = with pkgs; [ age coreutils diffutils gnugrep openssh sops ];
        text = builtins.readFile ./commands/wintix-secrets-enroll.sh;
      };
      wintixWorkBootstrap = pkgs.writeShellApplication {
        name = "wintix-work-bootstrap";
        runtimeInputs = with pkgs; [ coreutils git openssh ];
        text = builtins.readFile ./commands/wintix-work-bootstrap.sh;
      };
      mkWorkstation = hostModule: nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = { inherit self unstablePkgs sops-nix; };
        modules = [
          disko.nixosModules.disko
          hostModule
          home-manager.nixosModules.home-manager
          {
            home-manager.sharedModules = [ plasma-manager.homeModules.plasma-manager ];
            home-manager.extraSpecialArgs = { inherit sops-nix unstablePkgs; };
          }
        ];
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
      nixosConfigurations = {
        desktop = mkWorkstation ./hosts/desktop/default.nix;
        work-laptop = mkWorkstation ./hosts/work-laptop/default.nix;
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
        wintix-work-bootstrap = wintixWorkBootstrap;
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

      checks.${system} = {
        brave-config =
          let
            desktopConfig = self.nixosConfigurations.desktop.config;
            workConfig = self.nixosConfigurations.work-laptop.config;
            defaultPolicy = pkgs.writeText "brave-default-policy.json" (
              desktopConfig.environment.etc."brave/policies/managed/default.json".text
            );
            extraPolicy = pkgs.writeText "brave-extra-policy.json" (
              desktopConfig.environment.etc."brave/policies/managed/extra.json".text
            );
            expectedExtensionIds = [
              "mlomiejdfkolichcflejclcbmpeaniij"
              "mnjggcdmjocbbbhaepdhchncahnbgone"
              "cimiefiiaegbelhefglklhhakcgmhkai"
              "nngceckbapebfimnlniiiahkandclblb"
            ];
            januaryHome = desktopConfig.home-manager.users.january;
            ksledzHome = workConfig.home-manager.users.ksledz;
            januaryActivation = januaryHome.home.activationPackage;
            ksledzActivation = ksledzHome.home.activationPackage;
            extensionIds = home: map (extension: extension.id) home.programs.brave.extensions;
            expectedMimeApps = {
              "x-scheme-handler/http" = [ "com.brave.Browser.desktop" ];
              "x-scheme-handler/https" = [ "com.brave.Browser.desktop" ];
              "text/html" = [ "com.brave.Browser.desktop" ];
            };
          in
          assert januaryHome.programs.brave.enable;
          assert ksledzHome.programs.brave.enable;
          assert extensionIds januaryHome == expectedExtensionIds;
          assert extensionIds ksledzHome == expectedExtensionIds;
          assert januaryHome.xdg.mimeApps.defaultApplications == expectedMimeApps;
          assert ksledzHome.xdg.mimeApps.defaultApplications == expectedMimeApps;
          assert desktopConfig.programs.chromium.enablePlasmaBrowserIntegration;
          assert !(builtins.elem pkgs.brave desktopConfig.environment.systemPackages);
          pkgs.runCommand "wintix-brave-config-test" {
            nativeBuildInputs = with pkgs; [ jq ];
          } ''
            jq -e '
              .DefaultSearchProviderEnabled == true and
              .DefaultSearchProviderSearchURL == "https://www.google.com/search?q={searchTerms}" and
              .DefaultSearchProviderSuggestURL == "{google:baseURL}complete/search?output=chrome&q={searchTerms}" and
              length == 3
            ' ${defaultPolicy} >/dev/null
            jq -e '
              .ShowHomeButton == true and
              .ShowFullUrlsInAddressBar == true and
              .DefaultSearchProviderName == "Google" and
              .SpellcheckLanguage == ["en-US", "pl"] and
              .BraveRewardsDisabled == true and
              .BraveWalletDisabled == true and
              .BraveAIChatEnabled == false and
              length == 7
            ' ${extraPolicy} >/dev/null
            test -e ${desktopConfig.environment.etc."chromium/native-messaging-hosts/org.kde.plasma.browser_integration.json".source}
            test -e ${januaryHome.programs.brave.finalPackage}/share/applications/com.brave.Browser.desktop
            for generation in ${januaryActivation} ${ksledzActivation}; do
              for extension in ${builtins.concatStringsSep " " expectedExtensionIds}; do
                declaration="$generation/home-files/.config/BraveSoftware/Brave-Browser/External Extensions/$extension.json"
                jq -e '.external_update_url == "https://clients2.google.com/service/update2/crx"' "$declaration" >/dev/null
              done
              grep -q '^text/html=com.brave.Browser.desktop$' "$generation/home-files/.config/mimeapps.list"
              grep -q '^x-scheme-handler/http=com.brave.Browser.desktop$' "$generation/home-files/.config/mimeapps.list"
              grep -q '^x-scheme-handler/https=com.brave.Browser.desktop$' "$generation/home-files/.config/mimeapps.list"
            done
            touch "$out"
          '';

        brave-reconcile = pkgs.runCommand "wintix-brave-reconcile-test" {
          nativeBuildInputs = with pkgs; [
            bash
            coreutils
            findutils
            gnugrep
            jq
          ];
        } ''
          bash ${./tests/brave-reconcile-test.sh} ${./.}
          touch "$out"
        '';

        architecture = pkgs.runCommand "wintix-architecture-test" {
          nativeBuildInputs = with pkgs; [ bash coreutils findutils gnugrep ripgrep ];
        } ''
          bash ${./tests}/architecture-test.sh ${./.}
          touch "$out"
        '';
        plasma-panel = pkgs.runCommand "wintix-plasma-panel-test" {
          nativeBuildInputs = with pkgs; [ bash coreutils gnugrep ripgrep ];
        } ''
          bash ${./tests}/plasma-panel-test.sh ${./.}
          touch "$out"
        '';
        installer = pkgs.runCommand "wintix-installer-test" {
          nativeBuildInputs = with pkgs; [
            bash
            coreutils
            findutils
            gawk
            git
            gnugrep
            gnused
            jq
            util-linux
          ];
        } ''
          bash ${./installer}/tests/free-regions-test.sh
          bash ${./installer}/tests/installer-test.sh
          touch "$out"
        '';
        update = pkgs.runCommand "wintix-update-test" {
          nativeBuildInputs = with pkgs; [ bash coreutils git gnugrep ];
        } ''
          bash ${./commands}/tests/wintix-update-test.sh
          touch "$out"
        '';
        work-bootstrap = pkgs.runCommand "wintix-work-bootstrap-test" {
          nativeBuildInputs = with pkgs; [ bash coreutils diffutils findutils git gnugrep ];
        } ''
          bash ${./commands}/tests/wintix-work-bootstrap-test.sh
          touch "$out"
        '';
        secrets-bootstrap = pkgs.runCommand "wintix-secrets-bootstrap-test" {
          nativeBuildInputs = with pkgs; [
            bash
            coreutils
            gnugrep
          ];
        } ''
          bash ${./commands}/tests/wintix-secrets-bootstrap-test.sh
          touch "$out"
        '';

        secrets-enroll = pkgs.runCommand "wintix-secrets-enroll-test" {
          nativeBuildInputs = with pkgs; [
            bash
            coreutils
            diffutils
            gnugrep
            gnused
          ];
        } ''
          bash ${./commands}/tests/wintix-secrets-enroll-test.sh
          touch "$out"
        '';

        secrets-enroll-sops = pkgs.runCommand "wintix-secrets-enroll-sops-test" {
          nativeBuildInputs = with pkgs; [
            age
            bash
            coreutils
            diffutils
            gnugrep
            openssh
            sops
          ];
        } ''
          bash ${./commands}/tests/wintix-secrets-enroll-sops-test.sh
          touch "$out"
        '';
      };

      apps.${system}.install = {
        type = "app";
        program = "${self.packages.${system}.installer}/bin/wintix-install";
      };
    };
}
