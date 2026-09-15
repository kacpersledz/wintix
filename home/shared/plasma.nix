{ pkgs, lib, config, ... }:

let
  pathWallpaper = import ../../wallpaper.nix { inherit pkgs; };
in
{
  options.wintix.plasma.launchers = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    description = "Ordered desktop-entry IDs pinned to the Plasma task manager.";
  };

  config.wintix.plasma.launchers = [
    "applications:brave-browser.desktop"
    "applications:org.kde.dolphin.desktop"
    "applications:org.kde.konsole.desktop"
  ];

  config.xdg.configFile."wintix/plasma-launchers.json".text =
    builtins.toJSON { launchers = config.wintix.plasma.launchers; };

  config.programs.plasma = {
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

    kwin.edgeBarrier = 40;

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

    # Bottom-panel state is reconciled explicitly after Wintix rebuild/update,
    # never while Plasma is still initializing at login.
  };
}
