#!/usr/bin/env bash
set -euo pipefail

if [[ $(id -u) -eq 0 ]]; then
  printf 'wintix-rebuild: run this command as your normal user; it will request administrator privileges when needed\n' >&2
  exit 1
fi

WINTIX_PATH="${WINTIX_PATH:-$HOME/.wintix}"
WINTIX_CONFIGURATION_FILE=${WINTIX_CONFIGURATION_FILE:-/etc/wintix/configuration}

if [[ ! -f $WINTIX_CONFIGURATION_FILE ]]; then
  printf 'wintix-rebuild: missing installed configuration selector: %s\n' "$WINTIX_CONFIGURATION_FILE" >&2
  exit 1
fi
IFS= read -r WINTIX_CONFIGURATION < "$WINTIX_CONFIGURATION_FILE"
if [[ ! $WINTIX_CONFIGURATION =~ ^[a-zA-Z0-9_-]+$ ]]; then
  printf 'wintix-rebuild: invalid installed configuration selector.\n' >&2
  exit 1
fi

if ! NIXOS_REBUILD=$(command -v nixos-rebuild); then
  printf 'wintix-rebuild: nixos-rebuild is not available on PATH.\n' >&2
  exit 1
fi
if ! command -v sudo >/dev/null 2>&1; then
  printf 'wintix-rebuild: sudo is not available on PATH.\n' >&2
  exit 1
fi
if [[ ! -d $WINTIX_PATH ]]; then
  printf 'wintix-rebuild: WINTIX_PATH does not exist or is not a directory: %s\n' "$WINTIX_PATH" >&2
  exit 1
fi

if ! sudo -v; then
  printf 'wintix-rebuild: could not validate administrator privileges; no system changes were made.\n' >&2
  exit 1
fi

# The checkout intentionally marks machine-local generated modules
# skip-worktree. Use an explicit path flake so Nix reads their working-tree
# contents rather than the clean Git index stubs.
if ! sudo "$NIXOS_REBUILD" switch --flake "path:$WINTIX_PATH#$WINTIX_CONFIGURATION"; then
  printf 'wintix-rebuild: nixos-rebuild failed; Plasma reconciliation was not run.\n' >&2
  exit 1
fi

wintix-plasma-reconcile
