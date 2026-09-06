{ config, lib, ... }:
{
  imports = [ ./machine-generated.nix ];

  options.wintix.configuration = lib.mkOption {
    type = lib.types.str;
    default = "desktop";
    description = "Locally installed Wintix flake configuration name.";
  };

  environment.etc."wintix/configuration".text = "${config.wintix.configuration}\n";
}
