#!/usr/bin/env bash
set -euo pipefail

command_name=$(basename "$0")
if [[ $(id -u) -eq 0 ]]; then
  printf '%s: run this command as your normal user; it will request administrator privileges when needed\n' "$command_name" >&2
  exit 1
fi

case "$command_name" in
  wintix-charge-care) mode=care ;;
  wintix-charge-full) mode=full ;;
  *)
    printf '%s: unsupported command name\n' "$command_name" >&2
    exit 2
    ;;
esac

if ! command -v sudo >/dev/null 2>&1; then
  printf '%s: sudo is not available on PATH\n' "$command_name" >&2
  exit 1
fi

exec sudo @batteryChargeHelper@ "$mode"
