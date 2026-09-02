#!/usr/bin/env bash
# Shared presentation and failure helpers.  Never enable shell tracing here:
# this installer intentionally holds short-lived password variables.

set -eEuo pipefail

readonly WINTIX_GIT_URL="git@github.com:kacpersledz/wintix.git"
readonly WINTIX_FLAKE_REF="github:kacpersledz/wintix"
readonly MOUNT_POINT=/mnt

info() { gum style --foreground 6 "› $*" >&2; }
success() { gum style --foreground 2 "✓ $*" >&2; }
warn() { gum style --foreground 3 "! $*" >&2; }
die() { gum style --foreground 1 "Error: $*" >&2; exit 1; }

require_command() { command -v "$1" >/dev/null || die "Required command is unavailable: $1"; }

confirm_destructive() {
  local entered
  gum style --foreground 1 --bold "This operation is destructive."
  entered=$(gum input --prompt "Type ERASE to continue: ")
  [[ $entered == ERASE ]] || die "Confirmation did not match; no disk changes were made."
}

read_password() {
  local first second
  first=$(gum input --password --prompt "$1: ")
  second=$(gum input --password --prompt "Confirm $1: ")
  [[ -n $first ]] || die "Password may not be empty."
  [[ $first == "$second" ]] || die "Passwords do not match."
  printf '%s' "$first"
}
