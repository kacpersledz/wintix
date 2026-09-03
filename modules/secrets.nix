{ lib, ... }:

let
  enabled = builtins.getEnv "WINTIX_SECRETS_ENABLED" == "1";
  # Keep this a string so evaluation can explain the deliberately absent
  # enrollment artifact instead of failing while coercing a missing path.
  encryptedSecret = "${toString ../.}/secrets/github-ssh-key.yaml";
in
{
  config = lib.mkIf enabled {
    assertions = [
      {
        assertion = builtins.pathExists encryptedSecret;
        message = "Wintix secrets are enabled, but secrets/github-ssh-key.yaml has not been enrolled; see docs/secrets.md.";
      }
    ];

    sops = {
      age.keyFile = "/home/january/.config/sops/age/keys.txt";
      defaultSopsFile = encryptedSecret;
      secrets.wintix-github-ssh = {
        key = "github_ssh_private_key";
        owner = "january";
        group = "users";
        mode = "0400";
      };
    };
  };
}
