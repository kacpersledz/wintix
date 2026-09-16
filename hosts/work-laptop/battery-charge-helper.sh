#!/usr/bin/env bash
set -euo pipefail

mode=${1:-}
case "$mode" in
  care)
    desired_start=70
    desired_end=80
    ;;
  full)
    desired_start=0
    desired_end=100
    ;;
  *)
    printf 'wintix-battery-charge: expected mode "care" or "full"\n' >&2
    exit 2
    ;;
esac

sysfs_root=${WINTIX_BATTERY_SYSFS_ROOT:-/sys/class/power_supply/BAT0}
start_file="$sysfs_root/charge_control_start_threshold"
end_file="$sysfs_root/charge_control_end_threshold"

for threshold_file in "$start_file" "$end_file"; do
  if [[ ! -e $threshold_file ]]; then
    printf 'wintix-battery-charge: battery threshold interface unavailable; missing %s\n' "$threshold_file" >&2
    exit 1
  fi
done

# Lower start first so changing either mode can never transiently put the start
# threshold above the end threshold.
printf '%s\n' 0 > "$start_file"
printf '%s\n' "$desired_end" > "$end_file"
printf '%s\n' "$desired_start" > "$start_file"

actual_start=$(<"$start_file")
actual_end=$(<"$end_file")
if [[ $actual_start != "$desired_start" || $actual_end != "$desired_end" ]]; then
  printf 'wintix-battery-charge: verification failed (wanted %s / %s, found %s / %s)\n' \
    "$desired_start" "$desired_end" "$actual_start" "$actual_end" >&2
  exit 1
fi
