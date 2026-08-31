{ config, pkgs, ... }:

{
  environment.systemPackages = with pkgs; [
    git
    codex
  ];
}
