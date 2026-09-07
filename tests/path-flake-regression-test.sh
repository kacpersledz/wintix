#!/usr/bin/env bash
set -euo pipefail

root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

# Machine-local generated modules are tracked with skip-worktree. Any command
# that evaluates or builds the installed checkout must therefore force path:
# flake semantics so Nix reads working-tree contents rather than Git index
# placeholder stubs.
grep -F 'nixos-install --root "$MOUNT_POINT" --flake "path:$checkout#$SELECTED_HOST"' \
  "$root/installer/install-system.sh"
grep -F 'exec sudo "$NIXOS_REBUILD" switch --flake "path:$WINTIX_PATH#$WINTIX_CONFIGURATION"' \
  "$root/commands/wintix-rebuild.sh"
grep -F 'nix flake check "path:$WINTIX_PATH"' \
  "$root/commands/wintix-update.sh"
grep -F 'sudo "$NIXOS_REBUILD" switch --flake "path:$WINTIX_PATH#$WINTIX_CONFIGURATION"' \
  "$root/commands/wintix-update.sh"

# The clean-checkout behavior remains intentional; the fix must not remove the
# machine-local skip-worktree contract.
grep -F 'update-index --skip-worktree modules/storage-generated.nix modules/hardware-generated.nix modules/machine-generated.nix' \
  "$root/installer/install-system.sh"

printf 'path flake regression tests passed\n'
