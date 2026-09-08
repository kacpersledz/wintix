{ sops-nix, ... }:

{
  imports = [
    ../shared/brave.nix
    ../shared/development.nix
    ../shared/plasma.nix
    ../shared/zsh.nix
    ../shared/git-ssh.nix
    sops-nix.homeManagerModules.sops
    ./git-ssh.nix
  ];

  home.username = "january";
  home.homeDirectory = "/home/january";
  home.stateVersion = "26.05";

  programs.zsh.shellAliases = {
    rebuild = "wintix-rebuild";
    update = "wintix-update";
    secrets-bootstrap = "wintix-secrets-bootstrap";
    secrets-enroll = "wintix-secrets-enroll";
  };
}
