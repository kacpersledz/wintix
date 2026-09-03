#!/usr/bin/env bash
set -euo pipefail

key_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/sops/age
key_file=$key_dir/keys.txt

umask 077
mkdir -p -- "$key_dir"
chmod 0700 -- "$key_dir"

if [[ -e $key_file ]]; then
  if [[ -f $key_file ]] && age-keygen -y "$key_file" >/dev/null 2>&1; then
    chmod 0600 -- "$key_file"
    printf 'A valid Wintix age identity is already installed at %s; nothing changed.\n' "$key_file"
    printf 'Next, run: wintix-rebuild\n'
    exit 0
  fi
  printf 'wintix-secrets-bootstrap: %s exists but is not a valid age identity; refusing to overwrite it.\n' "$key_file" >&2
  exit 1
fi

printf 'Paste the Wintix AGE-SECRET-KEY identity (input is hidden), then press Enter: ' >&2
IFS= read -r -s identity
printf '\n' >&2

tmp=$(mktemp "$key_dir/.keys.txt.XXXXXX")
cleanup() { rm -f -- "$tmp"; }
trap cleanup EXIT HUP INT TERM
printf '%s\n' "$identity" >"$tmp"
unset identity
chmod 0600 -- "$tmp"

if ! recipient=$(age-keygen -y "$tmp" 2>/dev/null); then
  printf 'wintix-secrets-bootstrap: malformed age identity; nothing was installed.\n' >&2
  exit 1
fi

mv -n -- "$tmp" "$key_file"
chmod 0600 -- "$key_file"
trap - EXIT HUP INT TERM
printf 'Installed age identity for recipient %s.\n' "$recipient"
printf 'Next, run: wintix-rebuild\n'
