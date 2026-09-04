{ pkgs, lib, self, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/desktop.nix
    ../../modules/development.nix
    ../../modules/storage.nix
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

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  zramSwap = {
    enable = true;
    memoryPercent = 50;
    algorithm = "zstd";
    priority = 100;
  };

  swapDevices = [
    {
      device = "/swap/swapfile";
      size = 32 * 1024; # Match installed RAM for hibernation.
      priority = 1;
    }
  ];

  networking.hostName = "nixos";

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

  programs.zsh.enable = true;

  # Secrets administration is an intentional supported workflow on Wintix.
  environment.systemPackages = with pkgs; [ age sops ];

  # Keep this at the NixOS release originally installed on this host.
  system.stateVersion = "26.05";
}
