{ pkgs, unstablePkgs, ... }:

{
  home.packages = [
    pkgs.nodejs_24
    pkgs.python3
  ];

  programs.vscode = {
    enable = true;
    package = unstablePkgs.vscode;
  };

  programs.codex = {
    enable = true;
    package = unstablePkgs.codex;
  };

  programs.java = {
    enable = true;
    package = pkgs.corretto21;
  };
}
