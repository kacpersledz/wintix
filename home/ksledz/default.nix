{ ... }:
{
  imports = [
    ../shared/development.nix
    ../shared/plasma.nix
    ../shared/zsh.nix
    ../shared/git-ssh.nix
  ];
  home.username = "ksledz";
  home.homeDirectory = "/home/ksledz";
  home.stateVersion = "26.05";
  programs.git.includes = [
    {
      condition = "gitdir:~/.wintix/";
      path = "~/.config/wintix/git-personal.inc";
    }
    {
      condition = "gitdir:~/Documents/Code/personal/";
      path = "~/.config/wintix/git-personal.inc";
    }
    {
      condition = "gitdir:~/Documents/Code/work/";
      path = "~/.config/wintix/git-work.inc";
    }
  ];
  programs.zsh.shellAliases = {
    rebuild = "wintix-rebuild";
    update = "wintix-update";
    work-bootstrap = "wintix-work-bootstrap";
  };
}
