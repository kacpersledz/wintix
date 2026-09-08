#!/usr/bin/env bash
set -euo pipefail

root=${1:-$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)}
script="$root/home/shared/brave-reconcile.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

fail() {
  printf 'brave reconcile test failed: %s\n' "$*" >&2
  exit 1
}

write_state() {
  local dir=$1
  shift
  mkdir -p "$dir"
  jq -n --args '$ARGS.positional | reduce .[] as $profile ({profile:{info_cache:{}}}; .profile.info_cache[$profile] = {})' "$@" > "$dir/Local State"
}

assert_owned_preferences() {
  jq -e '
    .brave.tabs.always_hide_tab_close_button == true and
    .brave.tabs.mute_indicator_not_clickable == true and
    .brave.new_tab_page.show_clock == true and
    .brave.new_tab_page.clock_format == "h24" and
    .brave.show_side_panel_button == false
  ' "$1" >/dev/null
}

# One profile; unrelated profile and Local State values survive.
one="$work/one"
write_state "$one" Default
jq '.unrelated = {keep: [1, 2, 3]}' "$one/Local State" > "$one/state.tmp"
mv "$one/state.tmp" "$one/Local State"
mkdir -p "$one/Default"
printf '%s\n' '{"unrelated":{"keep":"yes"},"brave":{"tabs":{"other":42}}}' > "$one/Default/Preferences"
bash "$script" "$one"
assert_owned_preferences "$one/Default/Preferences"
jq -e '.unrelated.keep == "yes" and .brave.tabs.other == 42' "$one/Default/Preferences" >/dev/null
jq -e '.unrelated.keep == [1,2,3] and .brave.widevine_opted_in == true' "$one/Local State" >/dev/null

# Multiple metadata-discovered profiles receive the same five preferences.
multi="$work/multi"
write_state "$multi" Default "Profile 1" "Person With Spaces"
for profile in Default "Profile 1" "Person With Spaces"; do
  mkdir -p "$multi/$profile"
  printf '%s\n' '{"preserved":true}' > "$multi/$profile/Preferences"
done
bash "$script" "$multi"
for profile in Default "Profile 1" "Person With Spaces"; do
  assert_owned_preferences "$multi/$profile/Preferences"
  jq -e '.preserved == true' "$multi/$profile/Preferences" >/dev/null
done

# Reconciliation is idempotent and preserves modes; no temporary files remain.
before=$(sha256sum "$multi/Local State" "$multi/Default/Preferences")
chmod 640 "$multi/Default/Preferences"
bash "$script" "$multi"
after=$(sha256sum "$multi/Local State" "$multi/Default/Preferences")
[[ "$before" == "$after" ]] || fail 'second run changed converged JSON'
[[ $(stat -c %a "$multi/Default/Preferences") == 640 ]] || fail 'file mode was not preserved'
! find "$multi" -name '*.wintix.*' -print -quit | grep -q . || fail 'temporary replacement file remained'

# Missing Brave state is handled by creating only minimal valid Local State.
fresh="$work/fresh"
bash "$script" "$fresh"
jq -e '. == {"brave":{"widevine_opted_in":true}}' "$fresh/Local State" >/dev/null
[[ $(stat -c %a "$fresh/Local State") == 600 ]] || fail 'fresh Local State mode is not private'

# Malformed JSON fails before any file is replaced.
malformed="$work/malformed"
write_state "$malformed" Default Broken
mkdir -p "$malformed/Default" "$malformed/Broken"
printf '%s\n' '{"preserved":true}' > "$malformed/Default/Preferences"
printf '%s\n' '{broken' > "$malformed/Broken/Preferences"
state_hash=$(sha256sum "$malformed/Local State")
pref_hash=$(sha256sum "$malformed/Default/Preferences")
if bash "$script" "$malformed" >/dev/null 2>&1; then fail 'malformed JSON unexpectedly succeeded'; fi
[[ "$state_hash" == "$(sha256sum "$malformed/Local State")" ]] || fail 'Local State changed after malformed JSON'
[[ "$pref_hash" == "$(sha256sum "$malformed/Default/Preferences")" ]] || fail 'valid profile changed before malformed profile failure'

# Malicious metadata and symlinked profiles cannot escape the data root.
unsafe="$work/unsafe"
outside="$work/outside"
mkdir -p "$unsafe/Good" "$outside"
printf '%s\n' '{"outside":true}' > "$outside/Preferences"
ln -s "$outside" "$unsafe/Escape"
jq -n '{profile:{info_cache:{"Good":{},"../outside":{},"Escape":{},"/tmp/absolute":{}}}}' > "$unsafe/Local State"
printf '%s\n' '{"good":true}' > "$unsafe/Good/Preferences"
outside_hash=$(sha256sum "$outside/Preferences")
bash "$script" "$unsafe" 2> "$unsafe/stderr"
assert_owned_preferences "$unsafe/Good/Preferences"
[[ "$outside_hash" == "$(sha256sum "$outside/Preferences")" ]] || fail 'unsafe profile escaped data root'
grep -q 'ignoring unsafe profile path' "$unsafe/stderr"

# A Chromium singleton lock causes a clear failure without mutation.
locked="$work/locked"
write_state "$locked" Default
mkdir -p "$locked/Default"
printf '%s\n' '{}' > "$locked/Default/Preferences"
ln -s 'test-host-123' "$locked/SingletonLock"
locked_hash=$(sha256sum "$locked/Local State")
if bash "$script" "$locked" > "$locked/stdout" 2> "$locked/stderr"; then fail 'running-browser lock unexpectedly succeeded'; fi
[[ "$locked_hash" == "$(sha256sum "$locked/Local State")" ]] || fail 'locked Local State changed'
grep -q 'Close Brave completely' "$locked/stderr"

# Invalid profile metadata is rejected without replacing Local State.
invalid_metadata="$work/invalid-metadata"
mkdir -p "$invalid_metadata"
printf '%s\n' '{"profile":{"info_cache":"not-an-object"},"preserved":true}' > "$invalid_metadata/Local State"
invalid_hash=$(sha256sum "$invalid_metadata/Local State")
if bash "$script" "$invalid_metadata" >/dev/null 2>&1; then fail 'invalid profile metadata unexpectedly succeeded'; fi
[[ "$invalid_hash" == "$(sha256sum "$invalid_metadata/Local State")" ]] || fail 'invalid metadata changed Local State'

printf 'brave reconciliation tests passed\n'
