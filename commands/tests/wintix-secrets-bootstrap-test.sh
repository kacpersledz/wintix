#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
trap 'rm -rf -- "$TEST_ROOT"' EXIT
mkdir -p "$TEST_ROOT/bin"

valid='test-valid-identity'
cat >"$TEST_ROOT/bin/age-keygen" <<'EOF'
#!/bin/sh
set -eu
[ "$#" -eq 2 ] && [ "$1" = -y ]
IFS= read -r candidate <"$2"
[ "$candidate" = test-valid-identity ]
printf '%s\n' age1testrecipient
EOF
chmod +x "$TEST_ROOT/bin/age-keygen"
cat >"$TEST_ROOT/bin/systemctl" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$TEST_ROOT/bin/systemctl"
export PATH="$TEST_ROOT/bin:$PATH"
export HOME="$TEST_ROOT/home"

# Root invocation is rejected before it can create root-owned configuration;
# EUID=1000 cannot override the actual effective UID in the user namespace.
if unshare --user --map-root-user -- true >/dev/null 2>&1; then
  root_command=(unshare --user --map-root-user -- env EUID=1000)
else
  printf 'id() { printf "0\\n"; }\n' >"$TEST_ROOT/root-bash-env"
  root_command=(env EUID=1000 BASH_ENV="$TEST_ROOT/root-bash-env")
fi
set +e
"${root_command[@]}" HOME="$TEST_ROOT/root-home" PATH="$PATH" bash "$SCRIPT_DIR/wintix-secrets-bootstrap.sh" \
  >"$TEST_ROOT/root-stdout" 2>"$TEST_ROOT/root-stderr" </dev/null
root_rc=$?
set -e
(( root_rc != 0 ))
grep -F 'run this command as your normal user' "$TEST_ROOT/root-stderr" >/dev/null
[[ ! -e $TEST_ROOT/root-home ]]

run() {
  stdout=$TEST_ROOT/stdout stderr=$TEST_ROOT/stderr
  if printf '%s\n' "$1" | bash "$SCRIPT_DIR/wintix-secrets-bootstrap.sh" >"$stdout" 2>"$stderr"; then rc=0; else rc=$?; fi
}

# Invalid input is rejected without leaving secret material or printing it.
run 'invalid-sensitive-value'
(( rc != 0 ))
[[ ! -e $HOME/.config/sops/age/keys.txt ]]
! grep -F 'invalid-sensitive-value' "$stdout" "$stderr"

# A valid identity is installed atomically with restrictive permissions.
run "$valid"
(( rc == 0 ))
[[ $(<"$HOME/.config/sops/age/keys.txt") == "$valid" ]]
[[ $(stat -c %a "$HOME/.config/sops/age") == 700 ]]
[[ $(stat -c %a "$HOME/.config/sops/age/keys.txt") == 600 ]]
! grep -F "$valid" "$stdout" "$stderr"

# Rerunning is idempotent and does not consume or expose replacement input.
before=$(sha256sum "$HOME/.config/sops/age/keys.txt")
run 'would-be-a-replacement'
(( rc == 0 ))
[[ $(sha256sum "$HOME/.config/sops/age/keys.txt") == "$before" ]]
grep -F 'nothing changed' "$stdout" >/dev/null
grep -F 'age1testrecipient' "$stdout" >/dev/null
! grep -F 'would-be-a-replacement' "$stdout" "$stderr"

# An existing malformed file is never overwritten.
printf '%s\n' malformed >"$HOME/.config/sops/age/keys.txt"
run "$valid"
(( rc != 0 ))
[[ $(<"$HOME/.config/sops/age/keys.txt") == malformed ]]
! grep -F "$valid" "$stdout" "$stderr"

printf 'wintix-secrets-bootstrap tests passed\n'
