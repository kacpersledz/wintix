{ pkgs, ... }:

let
  pathWallpaper = import ../../wallpaper.nix { inherit pkgs; };
in
{
  programs.plasma = {
    enable = true;
    # Keep Plasma configuration hybrid: only the settings below are managed.
    overrideConfig = false;

    # Declarative KWin rules are special: plasma-manager resets and owns
    # kwinrulesrc, so manual rules only persist when represented here.
    window-rules = [
      {
        description = "Brave Picture-in-Picture";

        match = {
          window-class = {
            value = "brave";
            type = "exact";
            match-whole = false;
          };

          title = {
            value = "Picture in picture";
            type = "exact";
          };

          window-types = [ "normal" ];
        };

        apply.above = {
          value = true;
          apply = "initially";
        };
      }
    ];

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

    # Own the canonical bottom-panel composition/order and selected widget
    # settings while preserving nested widget configuration and runtime IDs.
    startup.desktopScript = {
      task-manager = {
        text = builtins.readFile ./plasma/task-manager.js;
        runAlways = true;
      };
      system-tray = {
        text = builtins.readFile ./plasma/system-tray.js;
        runAlways = true;
      };
    };
  };
}
