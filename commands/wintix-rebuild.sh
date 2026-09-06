#!/usr/bin/env bash
set -euo pipefail

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

exec sudo "$NIXOS_REBUILD" switch --flake "$WINTIX_PATH#$WINTIX_CONFIGURATION"
