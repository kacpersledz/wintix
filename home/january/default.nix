{ ... }:

{
  imports = [
    ../shared/zsh.nix
  ];

  home.username = "january";
  home.homeDirectory = "/home/january";
  home.stateVersion = "26.05";

  programs.zsh.shellAliases = {
    rebuild = "sudo nixos-rebuild switch --flake ~/.wintix#desktop";
    update = "nix flake update --flake ~/.wintix && sudo nixos-rebuild switch --flake ~/.wintix#desktop";
  };
}
