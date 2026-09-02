#!/usr/bin/env bash
set -euo pipefail

WINTIX_PATH="${WINTIX_PATH:-$HOME/.wintix}"

if ! NIXOS_REBUILD=$(command -v nixos-rebuild); then
  printf 'wintix-rebuild: nixos-rebuild is not available on PATH.\n' >&2
  exit 1
fi

exec sudo "$NIXOS_REBUILD" switch --flake "$WINTIX_PATH#desktop"
