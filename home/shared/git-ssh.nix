{ lib, ... }:

let
  secretsEnabled = builtins.getEnv "WINTIX_SECRETS_ENABLED" == "1";
in
{
  programs.git = {
    enable = true;
    settings.user = {
      name = "kacpersledz";
      email = "casper.sledx@gmail.com";
    };
  };

  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    matchBlocks.github = lib.mkIf secretsEnabled {
      host = "github.com";
      hostname = "github.com";
      user = "git";
      identitiesOnly = true;
      identityFile = "/run/secrets/wintix-github-ssh";
    };
  };
}
