{ config, lib, ... }:
{
  imports = [ ./machine-generated.nix ];

  options.wintix.configuration = lib.mkOption {
    type = lib.types.str;
    default = "desktop";
    description = "Locally installed Wintix flake configuration name.";
  };

  options.wintix.swapSizeMiB = lib.mkOption {
    type = lib.types.nullOr lib.types.ints.positive;
    default = null;
    description = ''
      Machine-local persistent swap-file size in MiB. The installer sets this
      from detected physical memory; null keeps repository-only evaluation safe.
    '';
  };

  environment.etc."wintix/configuration".text = "${config.wintix.configuration}\n";
}
