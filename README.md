# Wintix

Wintix is a personal declarative NixOS configuration. It currently contains the `desktop` host.

## Fresh installation

1. Boot an x86_64 NixOS minimal or graphical installer ISO in UEFI mode.
2. Connect to the network.
3. Open a terminal and run:

```sh
sudo -i
export NIX_CONFIG='experimental-features = nix-command flakes'
nix run github:kacpersledz/wintix#install
```

The stock NixOS installer ISO may have `nix-command` and `flakes` disabled. The
`NIX_CONFIG` environment variable enables them for the initial `nix run` and is
inherited by the installer's child Nix commands.

4. Follow the Gum TUI and reboot when installation completes.

No manual clone is required. The installer creates the installed user's editable
`~/.wintix` checkout automatically.

The installer discovers the available Wintix hosts and their normal user. It
supports a whole-disk install, a genuinely contiguous 80 GiB-or-larger free
GPT region, or replacement of one existing 80 GiB-or-larger partition. Partial
installs require an existing FAT EFI System Partition of at least 2 GiB and
never resize, reformat, or recreate it. The final confirmation requires typing
the selected disk path. Disko asks for the LUKS passphrase separately from the
normal user's password.

The installer clones Wintix into the installed user's `~/.wintix` and replaces
the tracked empty `modules/storage-generated.nix` stub locally with the new
partition PARTUUID and ESP UUID. It marks that local replacement
`skip-worktree`: Git-backed flakes include it for both installation and normal
`nixos-rebuild --flake ~/.wintix#...`, while ordinary `git status`, commits,
and pulls do not stage or publish the machine-specific values. This keeps host
definitions versioned while keeping machine-specific storage identifiers local.

From any working directory, use these commands to rebuild or update the desktop configuration:

```sh
wintix-rebuild
wintix-update
```

The short `rebuild` and `update` Zsh aliases delegate to these commands. Set
`WINTIX_PATH` to use a different local checkout; otherwise they use
`$HOME/.wintix`. `wintix-update` requires a clean `master` checkout, advances
flake inputs, validates and switches the system, and commits and pushes only a
changed `flake.lock`.

## Manual / development storage provisioning

These commands are low-level development/debugging interfaces. Normal fresh
installation should use `nix run github:kacpersledz/wintix#install` instead.

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
