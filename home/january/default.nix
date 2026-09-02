{ ... }:

{
  imports = [
    ../shared/plasma.nix
    ../shared/zsh.nix
  ];

  home.username = "january";
  home.homeDirectory = "/home/january";
  home.stateVersion = "26.05";

  programs.zsh.shellAliases = {
    rebuild = "wintix-rebuild";
    update = "wintix-update";
  };
}
