#!/usr/bin/env bash
set -euo pipefail

WINTIX_PATH="${WINTIX_PATH:-$HOME/.wintix}"
STATUS_FILE=$(mktemp)
STAGED_FILE=$(mktemp)
trap 'rm -f -- "$STATUS_FILE" "$STAGED_FILE"' EXIT

die() {
  printf 'wintix-update: %s\n' "$*" >&2
  exit 1
}

for tool in git nix sudo nixos-rebuild; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    die "$tool is not available on PATH"
  fi
done

if [[ ! -d "$WINTIX_PATH" ]]; then
  die "WINTIX_PATH does not exist or is not a directory: $WINTIX_PATH"
fi

if [[ "$(git -C "$WINTIX_PATH" rev-parse --is-inside-work-tree 2>/dev/null || true)" != true ]]; then
  die "WINTIX_PATH is not a Git working tree: $WINTIX_PATH"
fi

branch=$(git -C "$WINTIX_PATH" symbolic-ref --quiet --short HEAD 2>/dev/null) || \
  die "repository is detached; checkout branch master before updating"
if [[ "$branch" != master ]]; then
  die "repository is on '$branch'; checkout master before updating"
fi

if ! git -C "$WINTIX_PATH" remote get-url origin >/dev/null 2>&1; then
  die "repository has no origin remote"
fi

if ! git -C "$WINTIX_PATH" -c user.useConfigOnly=true var GIT_AUTHOR_IDENT >/dev/null 2>&1 || \
  ! git -C "$WINTIX_PATH" -c user.useConfigOnly=true var GIT_COMMITTER_IDENT >/dev/null 2>&1; then
  die "Git author/committer identity is unavailable; configure user.name and user.email before updating"
fi

refresh_status() {
  if ! git -C "$WINTIX_PATH" status \
    --porcelain=v1 \
    --untracked-files=all \
    --ignore-submodules=none \
    -z >"$STATUS_FILE"; then
    die "could not inspect Git status"
  fi
}

require_clean() {
  local message=$1
  refresh_status
  if [[ -s "$STATUS_FILE" ]]; then
    die "$message"
  fi
}

require_only_lockfile() {
  local message=$1
  local entry path

  refresh_status
  while IFS= read -r -d '' entry; do
    if [[ ${#entry} -lt 4 ]]; then
      die "could not parse Git status while checking $message"
    fi
    path=${entry:3}
    if [[ "$path" != flake.lock ]]; then
      die "$message (unexpected path: $path)"
    fi
  done <"$STATUS_FILE"
}

require_staged_only_lockfile() {
  local entry count=0

  if ! git -C "$WINTIX_PATH" diff --cached --name-only -z -- >"$STAGED_FILE"; then
    die "could not inspect the staged Git paths"
  fi

  while IFS= read -r -d '' entry; do
    count=$((count + 1))
    if [[ "$entry" != flake.lock ]]; then
      die "refusing to commit: staged path is not flake.lock: $entry"
    fi
  done <"$STAGED_FILE"

  if (( count != 1 )); then
    die "refusing to commit: the staged path set must contain exactly flake.lock"
  fi
}

require_clean "working tree is dirty; commit or remove all tracked, staged, and untracked changes first"

if ! git -C "$WINTIX_PATH" fetch origin master; then
  die "could not fetch origin/master"
fi

head=$(git -C "$WINTIX_PATH" rev-parse --verify 'HEAD^{commit}') || \
  die "could not resolve local HEAD"
remote_head=$(git -C "$WINTIX_PATH" rev-parse --verify 'refs/remotes/origin/master^{commit}') || \
  die "could not resolve origin/master after fetching"

if [[ "$head" == "$remote_head" ]]; then
  :
elif git -C "$WINTIX_PATH" merge-base --is-ancestor "$head" "$remote_head"; then
  if ! git -C "$WINTIX_PATH" pull --ff-only origin master; then
    die "local master could not be fast-forwarded to origin/master"
  fi
elif git -C "$WINTIX_PATH" merge-base --is-ancestor "$remote_head" "$head"; then
  die "local master contains commits not present on origin/master; manual resolution is required"
else
  die "local master and origin/master have diverged; no automatic merge, rebase, or reset was performed"
fi

require_clean "repository is dirty after synchronizing with origin/master"

if ! nix flake update --flake "$WINTIX_PATH"; then
  die "nix flake update failed; no commit or push was performed"
fi

require_only_lockfile "unexpected Git changes after nix flake update; only flake.lock may be modified"

if ! nix flake check "$WINTIX_PATH"; then
  die "nix flake check failed; no commit or push was performed"
fi

require_only_lockfile "unexpected Git changes before rebuild; only flake.lock may be modified"

if ! NIXOS_REBUILD=$(command -v nixos-rebuild); then
  die "nixos-rebuild is not available on PATH"
fi
if ! sudo "$NIXOS_REBUILD" switch --flake "$WINTIX_PATH#desktop"; then
  die "nixos-rebuild failed; no commit or push was performed; flake.lock was left available for inspection"
fi

require_only_lockfile "unexpected Git changes after rebuild; only flake.lock may be modified"

if [[ ! -s "$STATUS_FILE" ]]; then
  printf 'Wintix is already up to date.\n'
  exit 0
fi

if ! git -C "$WINTIX_PATH" add -- flake.lock; then
  die "could not stage flake.lock"
fi

require_staged_only_lockfile
require_only_lockfile "unexpected Git changes before commit; only flake.lock may be modified"

if ! git -C "$WINTIX_PATH" commit -m 'chore: update flake inputs'; then
  die "could not commit flake.lock; no push was performed"
fi
commit=$(git -C "$WINTIX_PATH" rev-parse --short HEAD)

require_clean "unexpected Git changes after commit; refusing to push"

push_output=$(mktemp)
if git -C "$WINTIX_PATH" push origin master >"$push_output" 2>&1; then
  rm -f -- "$push_output"
  printf 'Updated flake inputs, rebuilt Wintix, and pushed commit %s.\n' "$commit"
  exit 0
fi

cat "$push_output" >&2
rm -f -- "$push_output"

if git -C "$WINTIX_PATH" fetch origin master >/dev/null 2>&1; then
  local_head=$(git -C "$WINTIX_PATH" rev-parse --verify 'HEAD^{commit}')
  remote_head=$(git -C "$WINTIX_PATH" rev-parse --verify 'refs/remotes/origin/master^{commit}')
  if [[ "$remote_head" != "$local_head" ]] && \
    ! git -C "$WINTIX_PATH" merge-base --is-ancestor "$remote_head" "$local_head"; then
    die "local update succeeded; lockfile commit $commit was created locally, but push was rejected because origin/master advanced. Manual Git reconciliation is required"
  fi
fi

die "local update succeeded and lockfile commit $commit was created locally, but push failed. Manual Git resolution is required"
