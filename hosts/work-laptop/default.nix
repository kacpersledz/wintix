{ pkgs, lib, self, ... }:
{
  imports = [ ../../modules/workstation.nix ];
  wintix.storage = {
    enable = true;
    mode = "selected-partition";
    device = lib.mkDefault "/dev/disk/by-partuuid/installer-generated";
    efiDevice = lib.mkDefault "/dev/disk/by-uuid/installer-generated";
  };
  networking.hostName = lib.mkDefault "work-laptop";
  networking.networkmanager.plugins = with pkgs; [
    networkmanager-openvpn
  ];
  wintix.configuration = lib.mkDefault "work-laptop";
  users.users.ksledz = {
    isNormalUser = true;
    description = "ksledz";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = [
      pkgs.kdePackages.kate
      self.packages.${pkgs.system}.wintix-rebuild
      self.packages.${pkgs.system}.wintix-update
      self.packages.${pkgs.system}.wintix-work-bootstrap
    ];
    shell = pkgs.zsh;
  };
  home-manager.users.ksledz = import ../../home/ksledz/default.nix;
}
