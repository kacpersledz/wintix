{ pkgs, lib, self, ajazz-time-correction-tool, ... }:
{
  imports = [
    ../../modules/workstation.nix
    ./battery-charge.nix
  ];
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
  services.pcscd.enable = true;
  services.udev.extraRules = ''
    # Allow members of the local users group to access Huawei HDC devices.
    SUBSYSTEM=="usb", ATTR{idVendor}=="12d1", ATTR{idProduct}=="5000", GROUP="users", MODE="0660"

    # Allow the Ajazz time correction tool to access the AK820 HID interfaces.
    SUBSYSTEM=="hidraw", ATTRS{idVendor}=="0c45", ATTRS{idProduct}=="8009", GROUP="users", MODE="0660"
  '';
  environment.systemPackages = [ pkgs.pcsc-tools ];
  systemd.sleep.settings.Sleep = {
    HibernateMode = "shutdown";
  };
  wintix.configuration = lib.mkDefault "work-laptop";
  users.users.ksledz = {
    isNormalUser = true;
    description = "ksledz";
    extraGroups = [ "networkmanager" "wheel" ];
    packages = [
      pkgs.kdePackages.kate
      ajazz-time-correction-tool.packages.${pkgs.stdenv.hostPlatform.system}.default
      self.packages.${pkgs.stdenv.hostPlatform.system}.wintix-rebuild
      self.packages.${pkgs.stdenv.hostPlatform.system}.wintix-update
      self.packages.${pkgs.stdenv.hostPlatform.system}.wintix-plasma-reconcile
      self.packages.${pkgs.stdenv.hostPlatform.system}.wintix-work-bootstrap
    ];
    shell = pkgs.zsh;
  };
  home-manager.users.ksledz = import ../../home/ksledz/default.nix;
}
