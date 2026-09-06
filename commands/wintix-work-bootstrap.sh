#!/usr/bin/env bash
set -euo pipefail

config_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/wintix
git_config=$config_dir/work-git.inc
ssh_dir=$HOME/.ssh
ssh_key=$ssh_dir/id_ed25519

printf 'Work Git user name: '
IFS= read -r git_name
printf 'Work Git email: '
IFS= read -r git_email
[[ -n $git_name && -n $git_email ]] || { printf 'Name and email must not be empty.\n' >&2; exit 1; }

umask 077
mkdir -p -- "$config_dir" "$ssh_dir"
chmod 0700 -- "$config_dir" "$ssh_dir"
tmp=$(mktemp "$config_dir/.work-git.inc.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT HUP INT TERM
git config --file "$tmp" user.name "$git_name"
git config --file "$tmp" user.email "$git_email"
mv -f -- "$tmp" "$git_config"
trap - EXIT HUP INT TERM
chmod 0600 -- "$git_config"
printf 'Stored work Git identity in %s.\n' "$git_config"

if [[ -e $ssh_key ]]; then
  [[ -f $ssh_key ]] || { printf '%s exists and is not a regular file; refusing to modify it.\n' "$ssh_key" >&2; exit 1; }
  printf 'Existing SSH private key kept unchanged: %s\n' "$ssh_key"
  if [[ ! -f $ssh_key.pub ]]; then
    ssh-keygen -y -f "$ssh_key" > "$ssh_key.pub"
    chmod 0644 -- "$ssh_key.pub"
  fi
else
  [[ ! -e $ssh_key.pub ]] || { printf '%s exists without its private key; refusing to overwrite anything.\n' "$ssh_key.pub" >&2; exit 1; }
  ssh-keygen -t ed25519 -C "$git_email" -f "$ssh_key"
fi
printf 'Register this public key with your employer Git provider:\n'
cat -- "$ssh_key.pub"
