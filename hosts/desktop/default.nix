{ pkgs, lib, self, ... }:

{
  imports = [
    ../../modules/workstation.nix
  ];

  # Reusable hosts contain only installer placeholders. The installed
  # machine's real PARTUUID and ESP UUID live in storage-generated.nix.
  wintix.storage = {
    enable = true;
    mode = "selected-partition";
    device = lib.mkDefault "/dev/disk/by-partuuid/installer-generated";
    efiDevice = lib.mkDefault "/dev/disk/by-uuid/installer-generated";
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
      self.packages.${pkgs.system}.wintix-plasma-reconcile
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
