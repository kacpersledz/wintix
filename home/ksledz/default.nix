{ ... }:
{
  imports = [
    ../shared/plasma.nix
    ../shared/zsh.nix
    ../shared/git-ssh.nix
  ];
  home.username = "ksledz";
  home.homeDirectory = "/home/ksledz";
  home.stateVersion = "26.05";
  programs.git.includes = [ { path = "~/.config/wintix/work-git.inc"; } ];
  programs.zsh.shellAliases = {
    rebuild = "wintix-rebuild";
    update = "wintix-update";
    work-bootstrap = "wintix-work-bootstrap";
  };
}
