#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
UPDATE_SCRIPT="$SCRIPT_DIR/wintix-update.sh"
TEST_ROOT=$(mktemp -d)
TEST_BIN="$TEST_ROOT/bin"
FAKE_LOG="$TEST_ROOT/fake.log"
mkdir -p "$TEST_BIN"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

export PATH="$TEST_BIN:$PATH"
export FAKE_LOG

write_fake_tools() {
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "nix %s\\n" "$*" >> "$FAKE_LOG"' \
    'if [[ "$1 $2" == "flake update" ]]; then' \
    '  repo=${4:?missing flake path}' \
    '  case ${FAKE_NIX_UPDATE_MODE:-unchanged} in' \
    '    unchanged) ;;' \
    '    lock) printf "updated\\n" >> "$repo/flake.lock" ;;' \
    '    other) printf "unexpected\\n" > "$repo/unrelated.txt" ;;' \
    '    staged-other) printf "unexpected\\n" > "$repo/unrelated.txt"; git -C "$repo" add -- unrelated.txt ;;' \
    '    *) printf "unknown fake update mode\\n" >&2; exit 90 ;;' \
    '  esac' \
    'elif [[ "$1 $2" == "flake check" ]]; then' \
    '  if [[ ${FAKE_NIX_CHECK_MODE:-pass} == fail ]]; then exit 91; fi' \
    'fi' > "$TEST_BIN/nix"
  chmod +x "$TEST_BIN/nix"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "sudo %s\\n" "$*" >> "$FAKE_LOG"' \
    'exec "$@"' > "$TEST_BIN/sudo"
  chmod +x "$TEST_BIN/sudo"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'printf "nixos-rebuild %s\\n" "$*" >> "$FAKE_LOG"' \
    'if [[ ${FAKE_REBUILD_MODE:-pass} == fail ]]; then exit 92; fi' \
    'if [[ -n ${FAKE_RACE_REPO:-} && ! -e ${FAKE_RACE_MARKER:-} ]]; then' \
    '  race_clone=${FAKE_RACE_CLONE:?missing race clone}' \
    '  race_origin=$(git -C "$FAKE_RACE_REPO" remote get-url origin)' \
    '  git clone --quiet "$race_origin" "$race_clone"' \
    '  git -C "$race_clone" config user.name test' \
    '  git -C "$race_clone" config user.email test@example.invalid' \
    '  printf "upstream\\n" > "$race_clone/upstream.txt"' \
    '  git -C "$race_clone" add -- upstream.txt' \
    '  git -C "$race_clone" commit --quiet -m "concurrent upstream change"' \
    '  git -C "$race_clone" push --quiet origin master' \
    '  touch "$FAKE_RACE_MARKER"' \
    'fi' > "$TEST_BIN/nixos-rebuild"
  chmod +x "$TEST_BIN/nixos-rebuild"
}

make_repo() {
  local name=$1
  local repo="$TEST_ROOT/$name"
  local origin="$TEST_ROOT/$name-origin.git"

  git init --quiet --bare --initial-branch=master "$origin"
  git init --quiet --initial-branch=master "$repo"
  git -C "$repo" config user.name test
  git -C "$repo" config user.email test@example.invalid
  printf 'placeholder\n' > "$repo/flake.nix"
  printf '{"nodes":{}}\n' > "$repo/flake.lock"
  git -C "$repo" add -- flake.nix flake.lock
  git -C "$repo" commit --quiet -m initial
  git -C "$repo" remote add origin "$origin"
  git -C "$repo" push --quiet --set-upstream origin master
  printf '%s\n' "$repo"
}

advance_remote() {
  local repo=$1
  local name=$2
  local origin clone

  origin=$(git -C "$repo" remote get-url origin)
  clone="$TEST_ROOT/$name"
  git clone --quiet "$origin" "$clone"
  git -C "$clone" config user.name test
  git -C "$clone" config user.email test@example.invalid
  printf 'remote change\n' > "$clone/remote.txt"
  git -C "$clone" add -- remote.txt
  git -C "$clone" commit --quiet -m "remote change"
  git -C "$clone" push --quiet origin master
}

run_update() {
  local repo=$1
  local mode=${2:-unchanged}

  : > "$FAKE_LOG"
  RUN_STDOUT="$TEST_ROOT/stdout"
  RUN_STDERR="$TEST_ROOT/stderr"
  if WINTIX_PATH="$repo" \
    FAKE_NIX_UPDATE_MODE="$mode" \
    FAKE_NIX_CHECK_MODE="${FAKE_NIX_CHECK_MODE:-pass}" \
    FAKE_REBUILD_MODE="${FAKE_REBUILD_MODE:-pass}" \
    FAKE_RACE_REPO="${FAKE_RACE_REPO:-}" \
    FAKE_RACE_MARKER="${FAKE_RACE_MARKER:-}" \
    FAKE_RACE_CLONE="${FAKE_RACE_CLONE:-}" \
    bash "$UPDATE_SCRIPT" >"$RUN_STDOUT" 2>"$RUN_STDERR"; then
    RUN_RC=0
  else
    RUN_RC=$?
  fi
}

assert_success() {
  if (( RUN_RC != 0 )); then
    printf 'expected success, got %d\n' "$RUN_RC" >&2
    cat "$RUN_STDERR" >&2
    exit 1
  fi
}

assert_failure() {
  if (( RUN_RC == 0 )); then
    printf 'expected failure\n' >&2
    cat "$RUN_STDOUT" >&2
    exit 1
  fi
}

assert_contains() {
  local file=$1
  local expected=$2
  if ! grep -F -- "$expected" "$file" >/dev/null; then
    printf 'expected %s to contain: %s\n' "$file" "$expected" >&2
    cat "$file" >&2
    exit 1
  fi
}

assert_clean() {
  local repo=$1
  if [[ -n $(git -C "$repo" status --porcelain=v1 --untracked-files=all) ]]; then
    printf 'expected clean repository: %s\n' "$repo" >&2
    git -C "$repo" status --short >&2
    exit 1
  fi
}

write_fake_tools

# Preflight rejects tracked changes, untracked files, and non-master branches.
repo=$(make_repo dirty)
printf 'changed\n' > "$repo/flake.nix"
run_update "$repo"
assert_failure
assert_contains "$RUN_STDERR" 'working tree is dirty'
[[ ! -s "$FAKE_LOG" ]]

repo=$(make_repo untracked)
printf 'unexpected\n' > "$repo/untracked.txt"
run_update "$repo"
assert_failure
assert_contains "$RUN_STDERR" 'working tree is dirty'

repo=$(make_repo wrong-branch)
git -C "$repo" checkout --quiet -b feature
run_update "$repo"
assert_failure
assert_contains "$RUN_STDERR" 'checkout master'

# Equal local and remote is accepted, and the rebuild still runs on the
# no-change path without creating a commit.
repo=$(make_repo equal)
before=$(git -C "$repo" rev-parse HEAD)
run_update "$repo"
assert_success
assert_contains "$RUN_STDOUT" 'Wintix is already up to date.'
[[ $(git -C "$repo" rev-parse HEAD) == "$before" ]]
assert_contains "$FAKE_LOG" 'nixos-rebuild'
assert_clean "$repo"

# A behind checkout fast-forwards before the update pipeline continues.
repo=$(make_repo behind)
advance_remote "$repo" behind-remote
run_update "$repo"
assert_success
[[ $(git -C "$repo" rev-parse HEAD) == $(git -C "$repo" rev-parse origin/master) ]]
assert_clean "$repo"

# Local-only commits and divergent histories are both rejected before Nix runs.
repo=$(make_repo ahead)
printf 'local\n' > "$repo/local.txt"
git -C "$repo" add -- local.txt
git -C "$repo" commit --quiet -m 'local change'
run_update "$repo"
assert_failure
assert_contains "$RUN_STDERR" 'commits not present on origin/master'
[[ ! -s "$FAKE_LOG" ]]

repo=$(make_repo diverged)
printf 'local\n' > "$repo/local.txt"
git -C "$repo" add -- local.txt
git -C "$repo" commit --quiet -m 'local change'
advance_remote "$repo" diverged-remote
run_update "$repo"
assert_failure
assert_contains "$RUN_STDERR" 'have diverged'
[[ ! -s "$FAKE_LOG" ]]

# A lock-only update is accepted and commits/pushes only flake.lock.
repo=$(make_repo lock-only)
run_update "$repo" lock
assert_success
assert_contains "$RUN_STDOUT" 'pushed commit'
[[ $(git -C "$repo" log -1 --format=%s) == 'chore: update flake inputs' ]]
[[ $(git -C "$repo" diff-tree --no-commit-id --name-only -r HEAD) == flake.lock ]]
[[ $(git -C "$repo" rev-parse HEAD) == $(git -C "$repo" rev-parse origin/master) ]]
assert_clean "$repo"

# Any other modified or staged path is rejected after flake update.
repo=$(make_repo other-dirty)
run_update "$repo" other
assert_failure
assert_contains "$RUN_STDERR" 'unexpected path: unrelated.txt'
[[ $(git -C "$repo" log -1 --format=%s) == initial ]]

repo=$(make_repo staged-other)
run_update "$repo" staged-other
assert_failure
assert_contains "$RUN_STDERR" 'unexpected path: unrelated.txt'
[[ $(git -C "$repo" log -1 --format=%s) == initial ]]

# Rebuild and validation failures leave the lockfile available and do not
# create a commit.
repo=$(make_repo rebuild-failure)
FAKE_REBUILD_MODE=fail run_update "$repo" lock
assert_failure
assert_contains "$RUN_STDERR" 'nixos-rebuild failed'
[[ $(git -C "$repo" log -1 --format=%s) == initial ]]
[[ -n $(git -C "$repo" status --porcelain=v1) ]]
FAKE_REBUILD_MODE=pass

repo=$(make_repo check-failure)
FAKE_NIX_CHECK_MODE=fail run_update "$repo" lock
assert_failure
assert_contains "$RUN_STDERR" 'nix flake check failed'
[[ $(git -C "$repo" log -1 --format=%s) == initial ]]
FAKE_NIX_CHECK_MODE=pass

# If origin/master advances between rebuild and push, keep the local commit
# and report that manual reconciliation is required.
repo=$(make_repo concurrent-push)
FAKE_RACE_REPO="$repo" \
  FAKE_RACE_MARKER="$TEST_ROOT/race.marker" \
  FAKE_RACE_CLONE="$TEST_ROOT/race-clone" \
  run_update "$repo" lock
assert_failure
assert_contains "$RUN_STDERR" 'origin/master advanced'
[[ $(git -C "$repo" log -1 --format=%s) == 'chore: update flake inputs' ]]
[[ $(git -C "$repo" diff-tree --no-commit-id --name-only -r HEAD) == flake.lock ]]
assert_clean "$repo"

printf 'wintix-update tests passed\n'
