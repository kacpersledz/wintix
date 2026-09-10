#!/usr/bin/env bash
set -euo pipefail

GDBUS=${WINTIX_GDBUS:-gdbus}
STRUCTURE_SCRIPT=${WINTIX_PLASMA_STRUCTURE_SCRIPT:-@structureScript@}
SETTINGS_SCRIPT=${WINTIX_PLASMA_SETTINGS_SCRIPT:-@settingsScript@}

skip() {
  printf 'Wintix Plasma reconciliation skipped: no live Plasma session.\n'
  exit 0
}

command -v "$GDBUS" >/dev/null 2>&1 || skip
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || skip

if ! owner=$($GDBUS call --session \
  --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
  --method org.freedesktop.DBus.NameHasOwner org.kde.plasmashell 2>/dev/null); then
  skip
fi
[[ $owner == *true* ]] || skip

evaluate() {
  local phase=$1 script=$2 output
  if ! output=$("$GDBUS" call --session --dest org.kde.plasmashell \
    --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript \
    "$(cat -- "$script")"); then
    printf 'wintix-plasma-reconcile: %s phase failed.\n' "$phase" >&2
    return 1
  fi
  if [[ $output == *WINTIX_ERROR:* ]]; then
    printf 'wintix-plasma-reconcile: %s phase failed: %s\n' "$phase" "$output" >&2
    return 1
  fi
}

evaluate structural "$STRUCTURE_SCRIPT" || exit 1
evaluate settings "$SETTINGS_SCRIPT" || exit 1
printf 'Wintix Plasma reconciliation complete.\n'
