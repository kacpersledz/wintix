{
  device,
  mode,
  efiDevice ? null,
}:

assert builtins.elem mode [
  "whole-disk"
  "selected-partition"
];
assert mode == "whole-disk" || efiDevice != null;
assert mode == "whole-disk" || efiDevice != device;

let
  btrfs = {
    type = "btrfs";
    # This only applies when Disko is explicitly run in a formatting mode.
    extraArgs = [ "-f" ];
    subvolumes = {
      root = {
        mountpoint = "/";
        mountOptions = [
          "compress=zstd"
          "noatime"
        ];
      };
      home = {
        mountpoint = "/home";
        mountOptions = [
          "compress=zstd"
          "noatime"
        ];
      };
      nix = {
        mountpoint = "/nix";
        mountOptions = [
          "compress=zstd"
          "noatime"
        ];
      };
      swap = {
        mountpoint = "/swap";
        mountOptions = [ "noatime" ];
      };
    };
  };

  encrypted = {
    type = "luks";
    name = "wintix-crypt";
    extraFormatArgs = [
      "--type"
      "luks2"
    ];
    settings.allowDiscards = true;
    # With no keyFile or passwordFile, Disko asks for and confirms a password.
    content = btrfs;
  };

  esp = {
    type = "filesystem";
    format = "vfat";
    mountpoint = "/boot";
    mountOptions = [ "umask=0077" ];
  };

  wholeDisk = {
    type = "disk";
    device = device;
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "2G";
          type = "EF00";
          content = esp;
        };
        wintix = {
          size = "100%";
          content = encrypted;
        };
      };
    };
  };

  selectedPartition = {
    type = "disk";
    device = device;
    # Installer #9 calls the non-destructive format,mount path for this mode.
    destroy = false;
    content = encrypted;
  };

  existingEsp = {
    type = "disk";
    device = efiDevice;
    # The installer validates and reuses this existing ESP; it is not a target.
    destroy = false;
    content = esp // {
      # Do not let the generic filesystem create hook format an invalid ESP.
      preCreateHook = ''
        if ! blkid -o value -s TYPE "${efiDevice}" | grep -qx vfat; then
          echo "The selected EFI device is not an existing vfat filesystem." >&2
          exit 1
        fi
      '';
    };
  };
in
if mode == "whole-disk" then
  {
    wintix = wholeDisk;
  }
else
  {
    boot = existingEsp;
    wintix = selectedPartition;
  }
