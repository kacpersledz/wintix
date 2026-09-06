{ unstablePkgs, ... }:
{
  # Work applications are installed here, while all account, profile, and
  # employer-specific state remains local to the machine.
  programs.thunderbird.enable = true;
  programs.obsidian.enable = true;

  home.packages = [ unstablePkgs.slack ];
}
