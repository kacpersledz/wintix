{ pkgs, ... }:

let
  pathWallpaper = import ../wallpaper.nix { inherit pkgs; };
in
{
  services.xserver.enable = true;

  services.displayManager.plasma-login-manager = {
    enable = true;
    settings = {
      Greeter.WallpaperPluginId = "org.kde.image";
      "Greeter][Wallpaper][org.kde.image][General".Image = "file://${pathWallpaper}";
    };
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

  hardware.bluetooth.enable = true;

  programs.chromium = {
    enable = true;
    enablePlasmaBrowserIntegration = true;
    defaultSearchProviderEnabled = true;
    defaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
    defaultSearchProviderSuggestURL = "{google:baseURL}complete/search?output=chrome&q={searchTerms}";
    extraOpts = {
      ShowHomeButton = true;
      ShowFullUrlsInAddressBar = true;
      DefaultSearchProviderName = "Google";
      SpellcheckLanguage = [
        "en-US"
        "pl"
      ];
      BraveRewardsDisabled = true;
      BraveWalletDisabled = true;
      BraveAIChatEnabled = false;
    };
  };
}
