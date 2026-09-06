{ config, lib, ... }:
{
  imports = [
    ./base.nix
    ./desktop.nix
    ./development.nix
    ./storage.nix
    ./hardware-generated.nix
    ./machine.nix
  ];
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  zramSwap = { enable = true; memoryPercent = 50; algorithm = "zstd"; priority = 100; };
  swapDevices = lib.optional (config.wintix.swapSizeMiB != null) {
    device = "/swap/swapfile";
    size = config.wintix.swapSizeMiB;
    priority = 1;
  };
  programs.zsh.enable = true;
  home-manager.useGlobalPkgs = true;
  system.stateVersion = "26.05";
}
