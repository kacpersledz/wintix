{ config, ... }:

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
    settings."github.com" = {
      HostName = "github.com";
      User = "git";
      IdentitiesOnly = true;
      IdentityFile = config.sops.secrets.wintix-github-ssh.path;
    };
  };

  sops = {
    age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/github-ssh-key.yaml;
    secrets.wintix-github-ssh = {
      key = "github_ssh_private_key";
      mode = "0400";
    };
  };

  systemd.user.services.sops-nix.Unit.ConditionPathExists =
    "%h/.config/sops/age/keys.txt";
}
