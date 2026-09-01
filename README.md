# Wintix

Wintix is a personal declarative NixOS configuration. It currently contains the `desktop` host.

Clone Wintix to `~/.wintix`.

From any working directory, use these commands to rebuild or update the desktop configuration:

```sh
rebuild
update
```

## Storage provisioning

Disko is part of the flake and is only run explicitly by the installer. A
normal `nixos-rebuild` evaluates the Disko module to obtain `fileSystems` and
`boot.initrd.luks.devices`; it does not execute Disko's formatting scripts.

The installer selects devices at runtime. For a new whole-disk layout:

```sh
nix run .#disko -- \
  --mode destroy,format,mount \
  --flake .#wintix-whole-disk \
  --argstr device /dev/nvme0n1
```

For a partition selected by the installer, pass the existing suitable ESP as
well. This path formats only the selected partition:

```sh
nix run .#disko -- \
  --mode format,mount \
  --flake .#wintix-selected-partition \
  --argstr device /dev/nvme0n1p3 \
  --argstr efiDevice /dev/nvme0n1p1
```

Disko prompts interactively for the initial LUKS2 passphrase. The selected
partition path expects the installer to validate and preserve the existing
ESP; it does not resize or recreate surrounding GPT entries. Both layouts use
Btrfs subvolumes mounted at `/`, `/home`, `/nix`, and `/swap`, so the existing
`/swap/swapfile` NixOS declaration remains usable for hibernation.
