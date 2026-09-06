{ pkgs, lib, self, ... }:

{
  imports = [
    ../../modules/workstation.nix
  ];

  # Stable identifiers keep the installed desktop independent of /dev/nvme names.
  # Installer-selected targets use the diskoConfigurations outputs in flake.nix.
  wintix.storage = {
    enable = true;
    mode = "selected-partition";
    # A locally generated file overrides these development-machine defaults on
    # installed systems. It is deliberately not versioned.
    device = lib.mkDefault "/dev/disk/by-partuuid/baea0b8f-19b3-4b5f-bf48-43762b786eea";
    efiDevice = lib.mkDefault "/dev/disk/by-uuid/051C-9FD4";
  };

  networking.hostName = lib.mkDefault "desktop";
  wintix.configuration = lib.mkDefault "desktop";

  users.users."january" = {
    isNormalUser = true;
    description = "january";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
    packages = with pkgs; [
      kdePackages.kate
      self.packages.${pkgs.system}.wintix-rebuild
      self.packages.${pkgs.system}.wintix-update
      self.packages.${pkgs.system}.wintix-secrets-bootstrap
      self.packages.${pkgs.system}.wintix-secrets-enroll
    ];
    shell = pkgs.zsh;
  };

  home-manager = {
    useGlobalPkgs = true;

    users.january = import ../../home/january/default.nix;
  };

  # Secrets administration is an intentional supported workflow on Wintix.
  environment.systemPackages = with pkgs; [ age sops ];

}
