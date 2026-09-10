# Wintix commands

Wintix has one privilege boundary: `wintix-install` is run as root, while every
installed `wintix-*` command is run as the normal user. Do not prefix installed
commands with `sudo`; they reject root invocation before touching user state.

## `wintix-install`

- **Purpose:** interactively install Wintix onto a machine.
- **Run as:** root.
- **Usage:** `nix run github:kacpersledz/wintix#install` from a root shell on a
  NixOS installer ISO.
- **What it changes:** partitions, filesystems, the installed system, and the
  selected user's initial checkout.
- **Privilege behavior:** the entire installer is root-only and fails closed for
  a non-root caller.
- **Prerequisites / safety constraints:** UEFI, network access, and explicit
  destructive-operation confirmation are required.

## `wintix-rebuild`

- **Purpose:** switch to the locally selected Wintix configuration.
- **Run as:** normal user.
- **Usage:** `wintix-rebuild`.
- **What it changes:** the active NixOS system; it then reconciles the current
  user's Plasma panel session.
- **Privilege behavior:** validates credentials early with `sudo -v`; only
  `nixos-rebuild switch` runs through `sudo`.
- **Prerequisites / safety constraints:** needs the installed configuration
  selector and a valid `WINTIX_PATH` checkout (default: `~/.wintix`).

## `wintix-update`

- **Purpose:** synchronize `master`, update flake inputs, validate, switch, and
  commit/push a lockfile-only change when needed.
- **Run as:** normal user.
- **Usage:** `wintix-update`.
- **What it changes:** the local checkout, possibly `flake.lock`, and the
  active NixOS system; it then reconciles the current user's Plasma session.
- **Privilege behavior:** validates credentials with `sudo -v` after local
  safety checks and before fetching or updating. Only `nixos-rebuild switch`
  is elevated; Git, Nix flake operations, and Plasma reconciliation remain
  unprivileged.
- **Prerequisites / safety constraints:** requires a clean `master` checkout,
  an `origin` remote, Git identity, and push access for a changed lockfile.

## `wintix-plasma-reconcile`

- **Purpose:** reconcile the current Plasma session's panel configuration.
- **Run as:** normal user.
- **Usage:** `wintix-plasma-reconcile`.
- **What it changes:** the current user's live Plasma session when available.
- **Privilege behavior:** never uses `sudo`.
- **Prerequisites / safety constraints:** no live Plasma session is a safe
  no-op; root invocation is an error rather than a skipped session.

## `wintix-secrets-bootstrap`

- **Purpose:** restore an existing age identity after a reinstall.
- **Run as:** normal user.
- **Usage:** `wintix-secrets-bootstrap`.
- **What it changes:** `~/.config/sops/age/keys.txt` and may restart the
  current user's `sops-nix` service.
- **Privilege behavior:** never uses `sudo`.
- **Prerequisites / safety constraints:** refuses to replace invalid or
  existing key material.

## `wintix-secrets-enroll`

- **Purpose:** create or deliberately re-encrypt device SSH secret material.
- **Run as:** normal user.
- **Usage:** `wintix-secrets-enroll [--use-existing-key] [--replace-encrypted]`.
- **What it changes:** user SSH keys and the checkout's encrypted secret file.
- **Privilege behavior:** never uses `sudo`.
- **Prerequisites / safety constraints:** requires a valid age identity and
  deliberate flags before reusing keys or replacing encrypted material.

## `wintix-work-bootstrap`

- **Purpose:** configure separate personal/work Git identities and SSH keys.
- **Run as:** normal user.
- **Usage:** `wintix-work-bootstrap`.
- **What it changes:** user Git include files, SSH keys, and work directories.
- **Privilege behavior:** never uses `sudo`.
- **Prerequisites / safety constraints:** refuses unsafe existing key states
  and prints public keys for manual provider registration.
