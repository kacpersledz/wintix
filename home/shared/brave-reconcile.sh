# shellcheck shell=bash
set -euo pipefail

data_dir=${1:-"${XDG_CONFIG_HOME:-$HOME/.config}/BraveSoftware/Brave-Browser"}
local_state="$data_dir/Local State"

die() {
  printf 'wintix-brave-reconcile: %s\n' "$*" >&2
  exit 1
}

check_not_running() {
  if [[ -e "$data_dir/SingletonLock" || -L "$data_dir/SingletonLock" ]]; then
    die "Brave appears to be running for $data_dir. Close Brave completely, then rerun the rebuild."
  fi
}

validate_object() {
  local file=$1
  jq -e '
    type == "object" and
    ((.profile.info_cache? // {}) | type == "object")
  ' "$file" >/dev/null 2>&1 \
    || die "refusing to modify malformed or non-object JSON: $file"
}

atomic_merge() {
  local file=$1 filter=$2 dir base temporary
  dir=$(dirname -- "$file")
  base=$(basename -- "$file")
  mkdir -p -- "$dir"
  temporary=$(mktemp "$dir/.${base}.wintix.XXXXXX")

  if [[ -e "$file" ]]; then
    jq "$filter" "$file" > "$temporary" \
      || {
        rm -f -- "$temporary"
        die "failed to merge JSON without changing $file"
      }
    chmod --reference="$file" "$temporary"
  else
    printf '{}\n' | jq "$filter" > "$temporary" \
      || {
        rm -f -- "$temporary"
        die "failed to create $file"
      }
    chmod 600 "$temporary"
  fi

  if [[ -e "$file" ]] && cmp -s -- "$temporary" "$file"; then
    rm -f -- "$temporary"
  else
    mv -f -- "$temporary" "$file"
  fi
}

check_not_running

profiles=()
if [[ -e "$local_state" ]]; then
  validate_object "$local_state"
  while IFS= read -r -d '' profile; do
    [[ -n "$profile" && "$profile" != "." && "$profile" != ".." && "$profile" != */* ]] || {
      printf 'wintix-brave-reconcile: ignoring unsafe profile path from Local State: %q\n' "$profile" >&2
      continue
    }

    profile_dir="$data_dir/$profile"
    preferences="$profile_dir/Preferences"
    [[ -d "$profile_dir" && ! -L "$profile_dir" && -f "$preferences" && ! -L "$preferences" ]] || continue

    canonical_data_dir=$(realpath -e -- "$data_dir")
    canonical_preferences=$(realpath -e -- "$preferences")
    [[ "$canonical_preferences" == "$canonical_data_dir"/* ]] || {
      printf 'wintix-brave-reconcile: ignoring profile outside Brave data directory: %q\n' "$profile" >&2
      continue
    }

    validate_object "$preferences"
    profiles+=("$preferences")
  done < <(jq -j '(.profile.info_cache // {}) | keys[] | ., "\u0000"' "$local_state")
fi

# Validate all inputs before the first write, then recheck the browser lock to
# minimize the race between validation and atomic replacement.
check_not_running

atomic_merge "$local_state" '.brave.widevine_opted_in = true'

profile_filter='
  .brave.tabs.always_hide_tab_close_button = true |
  .brave.tabs.mute_indicator_not_clickable = true |
  .brave.new_tab_page.show_clock = true |
  .brave.new_tab_page.clock_format = "h24" |
  .brave.show_side_panel_button = false
'

for preferences in "${profiles[@]}"; do
  atomic_merge "$preferences" "$profile_filter"
done
