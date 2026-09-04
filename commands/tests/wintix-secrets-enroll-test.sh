#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

cat >"$TEST_ROOT/bin/age-keygen" <<'EOF'
#!/usr/bin/env bash
[[ $1 == -y && -f $2 ]] || exit 1
[[ $(<"$2") == test-valid-age-identity ]] || exit 1
printf '%s\n' age1testrecipient
EOF
cat >"$TEST_ROOT/bin/ssh-keygen" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == -y ]]; then
  grep -q 'BEGIN OPENSSH PRIVATE KEY' "$3"
  [[ $(tail -c 1 "$3" | od -An -tx1 | tr -d '[:space:]') == 0a ]]
  printf 'ssh-ed25519 test-public embedded-comment\n'
  exit
fi
while (( $# )); do
  if [[ $1 == -f ]]; then shift; key=$1; fi
  shift
done
printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' test-private-material '-----END OPENSSH PRIVATE KEY-----' >"$key"
printf '%s\n' 'ssh-ed25519 test-public wintix-github' >"$key.pub"
EOF
cat >"$TEST_ROOT/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$SOPS_LOG"
if [[ $1 == --decrypt ]]; then
  printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' test-private-material '-----END OPENSSH PRIVATE KEY-----'
  exit
fi
printf '%s\n' 'github_ssh_private_key: ENC[AES256_GCM,data:c2FmZQ==,iv:test,tag:test,type:str]' 'sops:' '  age: []' '  version: 3.9.0'
EOF
chmod +x "$TEST_ROOT/bin/"*
export PATH="$TEST_ROOT/bin:$PATH"
export SOPS_LOG="$TEST_ROOT/sops.log"

reset_case() {
  export HOME="$TEST_ROOT/$1/home" WINTIX_PATH="$TEST_ROOT/$1/repo" XDG_RUNTIME_DIR="$TEST_ROOT/$1/run"
  mkdir -p "$HOME/.config/sops/age" "$WINTIX_PATH/secrets" "$XDG_RUNTIME_DIR"
  printf '%s\n' 'creation_rules:' '  - path_regex: secrets/[^/]+\.yaml$' '    age: age1testrecipient' >"$WINTIX_PATH/.sops.yaml"
  printf '%s\n' '# WINTIX_SOPS_ENROLLMENT_REQUIRED' '# no secret' >"$WINTIX_PATH/secrets/github-ssh-key.yaml"
  : >"$SOPS_LOG"
}
run_enroll() {
  stdout=$TEST_ROOT/stdout stderr=$TEST_ROOT/stderr
  if bash "$SCRIPT_DIR/wintix-secrets-enroll.sh" "$@" >"$stdout" 2>"$stderr"; then rc=0; else rc=$?; fi
}

reset_case missing; run_enroll; (( rc != 0 )); grep -F 'missing age identity' "$stderr" >/dev/null
reset_case invalid; printf '%s\n' invalid-sensitive-identity >"$HOME/.config/sops/age/keys.txt"
run_enroll; (( rc != 0 )); ! grep -F 'invalid-sensitive-identity' "$stdout" "$stderr"
reset_case recipient; printf '%s\n' test-valid-age-identity >"$HOME/.config/sops/age/keys.txt"
sed -i 's/age1testrecipient/age1wrong/' "$WINTIX_PATH/.sops.yaml"
run_enroll; (( rc != 0 )); grep -F 'not configured for age1testrecipient' "$stderr" >/dev/null

reset_case existing; printf '%s\n' test-valid-age-identity >"$HOME/.config/sops/age/keys.txt"; mkdir -p "$HOME/.ssh"
printf '%s\n' '-----BEGIN OPENSSH PRIVATE KEY-----' existing-sensitive-material '-----END OPENSSH PRIVATE KEY-----' >"$HOME/.ssh/wintix_github_ed25519"
printf '%s\n' ssh-ed25519-existing >"$HOME/.ssh/wintix_github_ed25519.pub"
before=$(sha256sum "$HOME/.ssh/wintix_github_ed25519"); run_enroll; (( rc != 0 ))
[[ $(sha256sum "$HOME/.ssh/wintix_github_ed25519") == "$before" ]]; ! grep -F 'existing-sensitive-material' "$stdout" "$stderr"

reset_case success; printf '%s\n' test-valid-age-identity >"$HOME/.config/sops/age/keys.txt"; run_enroll; (( rc == 0 ))
[[ -f $HOME/.ssh/wintix_github_ed25519 ]]; grep -F 'ssh-ed25519 test-public wintix-github' "$stdout" >/dev/null
grep -F -- '--encrypt --filename-override secrets/github-ssh-key.yaml' "$SOPS_LOG" >/dev/null
grep -F -- '--decrypt --input-type yaml --extract ["github_ssh_private_key"] --output-type binary' "$SOPS_LOG" >/dev/null
grep -q '^sops:' "$WINTIX_PATH/secrets/github-ssh-key.yaml"
! grep -F 'BEGIN OPENSSH PRIVATE KEY' "$WINTIX_PATH/secrets/github-ssh-key.yaml"; ! grep -F 'test-private-material' "$stdout" "$stderr"

key_before=$(sha256sum "$HOME/.ssh/wintix_github_ed25519"); encrypted_before=$(sha256sum "$WINTIX_PATH/secrets/github-ssh-key.yaml")
run_enroll; (( rc != 0 )); [[ $(sha256sum "$HOME/.ssh/wintix_github_ed25519") == "$key_before" ]]
[[ $(sha256sum "$WINTIX_PATH/secrets/github-ssh-key.yaml") == "$encrypted_before" ]]
run_enroll --use-existing-key --replace-encrypted; (( rc == 0 )); [[ $(sha256sum "$HOME/.ssh/wintix_github_ed25519") == "$key_before" ]]

# A decrypted scalar without the SSH key's final LF must be rejected before replacing ciphertext.
cat >"$TEST_ROOT/bin/sops" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == --decrypt ]]; then
  printf '%s' '-----BEGIN OPENSSH PRIVATE KEY-----
test-private-material
-----END OPENSSH PRIVATE KEY-----'
  exit
fi
printf '%s\n' 'github_ssh_private_key: ENC[AES256_GCM,data:c2FmZQ==,iv:test,tag:test,type:str]' 'sops:' '  age: []' '  version: 3.9.0'
EOF
chmod +x "$TEST_ROOT/bin/sops"
run_enroll --use-existing-key --replace-encrypted; (( rc != 0 )); grep -F 'not a valid OpenSSH private key' "$stderr" >/dev/null
[[ $(sha256sum "$WINTIX_PATH/secrets/github-ssh-key.yaml") == "$encrypted_before" ]]

cat >"$TEST_ROOT/bin/sops" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' 'github_ssh_private_key: |-' '  -----BEGIN OPENSSH PRIVATE KEY-----' 'sops:'
EOF
chmod +x "$TEST_ROOT/bin/sops"
run_enroll --use-existing-key --replace-encrypted; (( rc != 0 )); grep -F 'plaintext OpenSSH' "$stderr" >/dev/null
[[ $(sha256sum "$WINTIX_PATH/secrets/github-ssh-key.yaml") == "$encrypted_before" ]]

printf 'wintix-secrets-enroll tests passed\n'
