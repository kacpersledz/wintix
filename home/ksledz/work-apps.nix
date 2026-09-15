{ pkgs, unstablePkgs, ... }:
{
  # Work applications are installed here, while all account, profile, and
  # employer-specific state remains local to the machine.
  programs.thunderbird.enable = true;

  home.packages = [
    pkgs.obsidian
    unstablePkgs.slack
  ];

  # Obsidian identifies its native Wayland window as md.obsidian.Obsidian,
  # while nixpkgs installs obsidian.desktop. Provide the matching desktop ID
  # so Plasma can resolve the running window to Obsidian's icon.
  xdg.desktopEntries."md.obsidian.Obsidian" = {
    name = "Obsidian";
    exec = "${pkgs.obsidian}/bin/obsidian %u";
    icon = "obsidian";
    terminal = false;
    noDisplay = true;

    settings.StartupWMClass = "md.Obsidian";
  };
}
