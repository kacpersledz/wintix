{ pkgs, ... }:

let
  pathWallpaper = "${pkgs.kdePackages.plasma-workspace-wallpapers}/share/wallpapers/Path/contents/images/2560x1600.jpg";
in
{
  programs.plasma = {
    enable = true;
    # Keep Plasma configuration hybrid: only the settings below are managed.
    overrideConfig = false;

    workspace = {
      lookAndFeel = "org.kde.breezedark.desktop";
      wallpaper = pathWallpaper;
    };

    kscreenlocker.appearance.wallpaper = pathWallpaper;

    kwin.nightLight = {
      enable = true;
      mode = "location";
      location = {
        latitude = "51.25";
        longitude = "22.57";
      };
      temperature.night = 3500;
    };

    # Plasma 6's Klipper config schema stores its history limit here.
    configFile."klipperrc".General.MaxClipItems = 999;
  };
}
