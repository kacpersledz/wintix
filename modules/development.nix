{ pkgs, unstablePkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    unstablePkgs.codex
  ];
}
