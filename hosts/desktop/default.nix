{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/base.nix
    ../../modules/desktop.nix
    ../../modules/development.nix
  ];

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
    ];
    shell = pkgs.zsh;
  };

  home-manager = {
    useGlobalPkgs = true;

    users.january =
      import ../../home/january/default.nix;
  };

  programs.zsh.enable = true;

  # Keep this at the NixOS release originally installed on this host.
  system.stateVersion = "26.05";
}
