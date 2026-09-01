# Wintix

Wintix is a personal declarative NixOS configuration. It currently contains the `desktop` host.

Clone Wintix to `~/.wintix`.

## Fresh installation

From a booted x86_64 UEFI NixOS minimal or graphical installer ISO, connect to
the network and run:

```sh
sudo nix run github:kacpersledz/wintix#install
```

The Gum TUI discovers the available Wintix hosts and their normal user. It
supports a whole-disk install, a genuinely contiguous 80 GiB-or-larger free
GPT region, or replacement of one existing 80 GiB-or-larger partition. Partial
installs require an existing FAT EFI System Partition of at least 2 GiB and
never resize, reformat, or recreate it. The final confirmation requires typing
the selected disk path. Disko asks for the LUKS passphrase separately from the
normal user's password.

The installer clones Wintix into the installed user's `~/.wintix`, writes an
untracked `hosts/<host>/storage-generated.nix` there with the new partition
PARTUUID and ESP UUID, and installs from that checkout. This keeps the host
definition versioned while keeping machine-specific storage identifiers local.

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

For a partition selected by the installer, validate and reuse a suitable ESP
separately in the target NixOS configuration. The Disko command below
destructively replaces the contents of only the selected partition while
preserving its GPT entry and surrounding partitions:

```sh
nix run .#disko -- \
  --mode format,mount \
  --flake .#wintix-selected-partition \
  --argstr device /dev/nvme0n1p3
```

Disko prompts interactively for the initial LUKS2 passphrase. The selected
partition path explicitly wipes the selected partition's filesystem/LUKS
signatures before creating fresh LUKS2 and Btrfs contents. The existing ESP is
outside this Disko device tree: the installer validates/reuses it, mounts it at
`/boot`, and supplies its path through `wintix.storage.efiDevice` for the
NixOS configuration. Disko does not wipe, resize, or recreate that ESP or
surrounding GPT entries. Both layouts use Btrfs subvolumes mounted at `/`,
`/home`, `/nix`, and `/swap`, so the existing `/swap/swapfile` NixOS
declaration remains usable for hibernation.
