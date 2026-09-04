#!/usr/bin/env bash
set -euo pipefail

die() {
  printf 'wintix-secrets-enroll: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf 'Usage: wintix-secrets-enroll [--use-existing-key] [--replace-encrypted]\n'
}

use_existing=false
replace_encrypted=false
while (( $# )); do
  case $1 in
    --use-existing-key) use_existing=true ;;
    --replace-encrypted) replace_encrypted=true ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

config_home=${XDG_CONFIG_HOME:-"$HOME/.config"}
age_file=$config_home/sops/age/keys.txt
ssh_dir=$HOME/.ssh
ssh_key=$ssh_dir/wintix_github_ed25519
repo=${WINTIX_PATH:-"$HOME/.wintix"}
sops_config=$repo/.sops.yaml
encrypted_file=$repo/secrets/github-ssh-key.yaml
marker='# WINTIX_SOPS_ENROLLMENT_REQUIRED'

[[ -f $age_file ]] || die "missing age identity at $age_file; restore it with wintix-secrets-bootstrap first"
recipient=$(age-keygen -y "$age_file" 2>/dev/null) || die "invalid age identity at $age_file"
[[ $recipient == age1* ]] || die "age-keygen returned an invalid public recipient"
[[ -f $sops_config ]] || die "missing $sops_config"
if ! grep -E "^[[:space:]]*age:[[:space:]]*$recipient([[:space:]]*#.*)?$" "$sops_config" >/dev/null; then
  die ".sops.yaml is not configured for $recipient; replace the enrollment marker with this public recipient, review the change, then rerun"
fi

if [[ -e $encrypted_file ]] && ! grep -Fx -- "$marker" "$encrypted_file" >/dev/null; then
  $replace_encrypted || die "$encrypted_file already contains enrolled data; use --replace-encrypted only after reviewing the rotation plan"
fi

mkdir -p -- "$ssh_dir"
chmod 0700 -- "$ssh_dir"
if [[ -e $ssh_key || -e $ssh_key.pub ]]; then
  $use_existing || die "SSH key material already exists at $ssh_key; refusing to overwrite it (use --use-existing-key to re-encrypt it deliberately)"
  [[ -f $ssh_key && -f $ssh_key.pub ]] || die "incomplete existing SSH key pair at $ssh_key; refusing to modify it"
  derived_public=$(ssh-keygen -y -f "$ssh_key" 2>/dev/null) || die "existing SSH private key is invalid"
  IFS=' ' read -r public_type public_data _ <"$ssh_key.pub"
  [[ "$public_type $public_data" == "$derived_public" ]] || die "existing SSH public key does not match its private key"
else
  $use_existing && die "--use-existing-key was requested, but $ssh_key does not exist"
  ssh-keygen -q -t ed25519 -N '' -C 'wintix-github' -f "$ssh_key"
fi
chmod 0600 -- "$ssh_key"
chmod 0644 -- "$ssh_key.pub"

runtime_dir=${XDG_RUNTIME_DIR:-$config_home}
tmp_dir=$(mktemp -d "$runtime_dir/wintix-enroll.XXXXXX")
chmod 0700 -- "$tmp_dir"
plain=$tmp_dir/github-ssh-key.yaml
encrypted=$tmp_dir/github-ssh-key.yaml.enc
cleanup() { rm -rf -- "$tmp_dir"; }
trap cleanup EXIT HUP INT TERM
{
  printf 'github_ssh_private_key: |-\n'
  while IFS= read -r line || [[ -n $line ]]; do printf '  %s\n' "$line"; done <"$ssh_key"
} >"$plain"
chmod 0600 -- "$plain"

mkdir -p -- "$repo/secrets"
(cd "$repo" && sops --encrypt --filename-override secrets/github-ssh-key.yaml "$plain") >"$encrypted"
chmod 0600 -- "$encrypted"
grep -Eq '^sops:' "$encrypted" || die "SOPS output has no metadata section"
if grep -F 'BEGIN OPENSSH PRIVATE KEY' "$encrypted" >/dev/null; then
  die "SOPS output still contains a plaintext OpenSSH private-key header"
fi
sops --decrypt --input-type yaml --output-type yaml "$encrypted" >/dev/null || die "SOPS could not decrypt and validate its output"
mv -f -- "$encrypted" "$encrypted_file"
chmod 0600 -- "$encrypted_file"

printf 'GitHub SSH public key (safe to register):\n'
cat -- "$ssh_key.pub"
printf '\nRegister that public key with GitHub, commit only .sops.yaml and %s, then verify:\n' "$encrypted_file"
printf '  systemctl --user restart sops-nix\n  ssh -T git@github.com\n'
