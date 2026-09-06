#!/usr/bin/env bash
set -euo pipefail

config_dir=${XDG_CONFIG_HOME:-"$HOME/.config"}/wintix
ssh_dir=$HOME/.ssh
personal_key=$ssh_dir/id_ed25519_personal
work_key=$ssh_dir/id_ed25519_work
personal_config=$config_dir/git-personal.inc
work_config=$config_dir/git-work.inc

die() { printf 'wintix-work-bootstrap: %s\n' "$*" >&2; exit 1; }

read_identity() {
  local label=$1 name_var=$2 email_var=$3 name email
  printf '%s Git user name: ' "$label"
  IFS= read -r name
  printf '%s Git email: ' "$label"
  IFS= read -r email
  [[ -n $name && -n $email ]] || die "$label Git name and email must not be empty"
  printf -v "$name_var" '%s' "$name"
  printf -v "$email_var" '%s' "$email"
}

assert_key_state() {
  local label=$1 key=$2
  if [[ -e $key ]]; then
    [[ -f $key ]] || die "$label private key is not a regular file: $key"
    [[ ! -e $key.pub || -f $key.pub ]] || die "$label public key is not a regular file: $key.pub"
  elif [[ -e $key.pub ]]; then
    die "$label public key exists without its private key; refusing to overwrite either: $key.pub"
  fi
}

ensure_key() {
  local label=$1 key=$2 email=$3 tmp
  if [[ -e $key ]]; then
    printf 'Existing %s private key kept unchanged: %s\n' "$label" "$key"
    if [[ ! -e $key.pub ]]; then
      tmp=$(mktemp "$ssh_dir/.${key##*/}.pub.XXXXXX")
      if ! ssh-keygen -y -f "$key" > "$tmp"; then
        rm -f -- "$tmp"
        die "could not recreate the $label public key from $key"
      fi
      chmod 0644 -- "$tmp"
      mv -- "$tmp" "$key.pub"
    fi
  else
    printf 'Creating %s SSH key; ssh-keygen will ask for its passphrase.\n' "$label"
    ssh-keygen -t ed25519 -C "$email" -f "$key"
  fi
}

write_identity() {
  local path=$1 name=$2 email=$3 key=$4 tmp
  tmp=$(mktemp "$config_dir/.git-identity.XXXXXX")
  git config --file "$tmp" user.name "$name"
  git config --file "$tmp" user.email "$email"
  git config --file "$tmp" core.sshCommand "ssh -i \"\$HOME/.ssh/${key##*/}\" -o IdentitiesOnly=yes"
  chmod 0600 -- "$tmp"
  mv -f -- "$tmp" "$path"
}

read_identity Personal personal_name personal_email
read_identity Work work_name work_email

umask 077
mkdir -p -- "$config_dir" "$ssh_dir" "$HOME/Documents/Code/personal" "$HOME/Documents/Code/work"
chmod 0700 -- "$config_dir" "$ssh_dir"

# Validate both pairs before changing either one, especially the fail-closed
# orphan-public-key case.
assert_key_state personal "$personal_key"
assert_key_state work "$work_key"
ensure_key personal "$personal_key" "$personal_email"
ensure_key work "$work_key" "$work_email"
write_identity "$personal_config" "$personal_name" "$personal_email" "$personal_key"
write_identity "$work_config" "$work_name" "$work_email" "$work_key"

printf '\nPersonal GitHub public key (%s):\n' "$personal_key.pub"
cat -- "$personal_key.pub"
printf '\nWork Git-provider public key (%s):\n' "$work_key.pub"
cat -- "$work_key.pub"
printf '\nRegister each key manually with the named provider. No key was uploaded.\n'
