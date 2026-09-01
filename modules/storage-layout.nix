{
  device,
  mode,
}:

assert builtins.elem mode [
  "whole-disk"
  "selected-partition"
];

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
    # Keep the GPT entry and boundaries, but replace this partition's contents.
    destroy = false;
    preCreateHook = ''
      wipefs --all --force "${device}"
    '';
    content = encrypted;
  };
in
if mode == "whole-disk" then
  {
    wintix = wholeDisk;
  }
else
  {
    wintix = selectedPartition;
  }
