{ ... }:
{
  programs.git.enable = true;
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
  };
}
