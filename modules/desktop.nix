{ pkgs, ... }:

let
  pathWallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/Path/contents/images/2560x1600.jpg";
  sddmTheme = pkgs.runCommand "wintix-sddm-theme" { } ''
    mkdir -p "$out/share/sddm/themes"
    cp -r ${pkgs.kdePackages.plasma-desktop}/share/sddm/themes/breeze "$out/share/sddm/themes/wintix"
    chmod -R u+w "$out/share/sddm/themes/wintix"
    cat > "$out/share/sddm/themes/wintix/theme.conf.user" <<EOF
    [General]
    background=${pathWallpaper}
    EOF
  '';
in
{
  services.xserver.enable = true;

  services.displayManager.sddm = {
    enable = true;
    theme = "${sddmTheme}/share/sddm/themes/wintix";
  };
  services.desktopManager.plasma6.enable = true;

  services.xserver.xkb = {
    layout = "pl";
    variant = "";
  };

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.firefox.enable = true;

  environment.systemPackages = with pkgs; [
    brave
  ];

  hardware.bluetooth.enable = true;

  programs.chromium = {
    enable = true;
    enablePlasmaBrowserIntegration = true;
  };
}
