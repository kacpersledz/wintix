{ pkgs, unstablePkgs, ... }:
{
  # Work applications are installed here, while all account, profile, and
  # employer-specific state remains local to the machine.
  programs.thunderbird.enable = true;

  home.packages = [
    pkgs.obsidian
    unstablePkgs.slack
  ];
}
