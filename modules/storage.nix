{ config, lib, ... }:

let
  cfg = config.wintix.storage;
in
{
  options.wintix.storage = {
    enable = lib.mkEnableOption "Wintix Disko storage";

    mode = lib.mkOption {
      type = lib.types.enum [
        "whole-disk"
        "selected-partition"
      ];
      default = "selected-partition";
      description = "Whether Disko owns a whole disk or one existing partition.";
    };

    device = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Runtime-selected disk or partition to provision. Installer callers should
        pass a stable device path such as /dev/disk/by-partuuid/....
      '';
    };

    efiDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Existing EFI System Partition to mount in selected-partition mode.
        The installer is responsible for validating this partition before use.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.device != null;
        message = "wintix.storage.device must be set when Wintix storage is enabled.";
      }
      {
        assertion = cfg.device == null || lib.hasPrefix "/" cfg.device;
        message = "wintix.storage.device must be an absolute device path.";
      }
      {
        assertion = cfg.mode == "whole-disk" || cfg.efiDevice != null;
        message = "wintix.storage.efiDevice is required in selected-partition mode.";
      }
      {
        assertion = cfg.mode == "whole-disk" || cfg.efiDevice != cfg.device;
        message = "wintix.storage.efiDevice must differ from the selected storage device.";
      }
      {
        assertion = cfg.efiDevice == null || lib.hasPrefix "/" cfg.efiDevice;
        message = "wintix.storage.efiDevice must be an absolute device path.";
      }
    ];

    disko.devices.disk = import ./storage-layout.nix {
      inherit (cfg) device mode efiDevice;
    };
  };
}
