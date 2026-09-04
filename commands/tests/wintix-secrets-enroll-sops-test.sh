#!/usr/bin/env bash
set -euo pipefail

for tool in age-keygen cmp grep od sops ssh-keygen tail tr; do
  command -v "$tool" >/dev/null 2>&1 || {
    printf 'wintix-secrets-enroll SOPS test: missing %s\n' "$tool" >&2
    exit 1
  }
done

TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
cd "$TEST_ROOT"
mkdir secrets
umask 077

age-keygen -o age-identity.txt >/dev/null 2>&1
recipient=$(age-keygen -y age-identity.txt)
ssh-keygen -q -t ed25519 -N '' -C 'wintix-sops-regression' -f source-key
printf 'creation_rules:\n  - path_regex: secrets/[^/]+\\.yaml$\n    age: %s\n' "$recipient" >.sops.yaml
{
  printf 'github_ssh_private_key: |\n'
  while IFS= read -r line || [[ -n $line ]]; do
    printf '  %s\n' "$line"
  done <source-key
} >plain.yaml

export SOPS_AGE_KEY_FILE=$TEST_ROOT/age-identity.txt
sops --encrypt --filename-override secrets/github-ssh-key.yaml plain.yaml >github-ssh-key.yaml.enc
sops --decrypt \
  --input-type yaml \
  --extract '["github_ssh_private_key"]' \
  --output-type binary \
  github-ssh-key.yaml.enc >extracted-key

[[ $(tail -c 1 extracted-key | od -An -tx1 | tr -d '[:space:]') == 0a ]]
chmod 0600 extracted-key
ssh-keygen -y -f extracted-key >/dev/null
cmp -s -- source-key extracted-key
! grep -F 'BEGIN OPENSSH PRIVATE KEY' github-ssh-key.yaml.enc

printf 'wintix-secrets-enroll real SOPS round-trip test passed\n'
