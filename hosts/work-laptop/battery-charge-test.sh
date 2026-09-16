#!/usr/bin/env bash
set -euo pipefail

source_dir=${1:?usage: battery-charge-test.sh SOURCE_DIR}
helper="$source_dir/hosts/work-laptop/battery-charge-helper.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

make_battery() {
  rm -rf "$tmp/BAT0"
  mkdir -p "$tmp/BAT0"
  printf '%s\n' 70 > "$tmp/BAT0/charge_control_start_threshold"
  printf '%s\n' 80 > "$tmp/BAT0/charge_control_end_threshold"
}

make_battery
WINTIX_BATTERY_SYSFS_ROOT="$tmp/BAT0" bash "$helper" full
[[ $(<"$tmp/BAT0/charge_control_start_threshold") == 0 ]]
[[ $(<"$tmp/BAT0/charge_control_end_threshold") == 100 ]]

WINTIX_BATTERY_SYSFS_ROOT="$tmp/BAT0" bash "$helper" care
[[ $(<"$tmp/BAT0/charge_control_start_threshold") == 70 ]]
[[ $(<"$tmp/BAT0/charge_control_end_threshold") == 80 ]]

rm "$tmp/BAT0/charge_control_end_threshold"
if WINTIX_BATTERY_SYSFS_ROOT="$tmp/BAT0" bash "$helper" care 2>"$tmp/error"; then
  echo 'battery-charge-test: missing threshold interface unexpectedly succeeded' >&2
  exit 1
fi
grep -F 'battery threshold interface unavailable; missing' "$tmp/error" >/dev/null
grep -F 'charge_control_end_threshold' "$tmp/error" >/dev/null

# Exercise both normal-user entry points with a fake sudo boundary. The fake
# id makes this root-owned build sandbox behave like an unprivileged caller.
mkdir "$tmp/bin"
cat > "$tmp/bin/id" <<'EOF'
#!/usr/bin/env bash
printf '1000\n'
EOF
cat > "$tmp/bin/sudo" <<'EOF'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$WINTIX_TEST_LOG"
exec "$@"
EOF
chmod +x "$tmp/bin/id" "$tmp/bin/sudo"
sed "s|@batteryChargeHelper@|$helper|" \
  "$source_dir/hosts/work-laptop/battery-charge-command.sh" > "$tmp/bin/wintix-charge-full"
cp "$tmp/bin/wintix-charge-full" "$tmp/bin/wintix-charge-care"
chmod +x "$tmp/bin/wintix-charge-full" "$tmp/bin/wintix-charge-care"

make_battery
export WINTIX_BATTERY_SYSFS_ROOT="$tmp/BAT0"
export WINTIX_TEST_LOG="$tmp/sudo.log"
PATH="$tmp/bin:$PATH" "$tmp/bin/wintix-charge-full"
[[ $(<"$tmp/BAT0/charge_control_start_threshold") == 0 ]]
[[ $(<"$tmp/BAT0/charge_control_end_threshold") == 100 ]]
PATH="$tmp/bin:$PATH" "$tmp/bin/wintix-charge-care"
[[ $(<"$tmp/BAT0/charge_control_start_threshold") == 70 ]]
[[ $(<"$tmp/BAT0/charge_control_end_threshold") == 80 ]]
[[ $(wc -l < "$tmp/sudo.log") == 2 ]]

echo 'battery-charge-test: ok'
