#!/usr/bin/env bash
set -euo pipefail

WINTIX_PATH="${WINTIX_PATH:-$HOME/.wintix}"

if ! NIXOS_REBUILD=$(command -v nixos-rebuild); then
  printf 'wintix-rebuild: nixos-rebuild is not available on PATH.\n' >&2
  exit 1
fi

if [[ -r ${XDG_CONFIG_HOME:-$HOME/.config}/sops/age/keys.txt ]]; then
  export WINTIX_SECRETS_ENABLED=1
  exec sudo --preserve-env=WINTIX_SECRETS_ENABLED "$NIXOS_REBUILD" switch --impure --flake "$WINTIX_PATH#desktop"
fi

exec sudo "$NIXOS_REBUILD" switch --flake "$WINTIX_PATH#desktop"
