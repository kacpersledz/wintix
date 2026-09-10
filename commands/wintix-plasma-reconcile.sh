#!/usr/bin/env bash
set -euo pipefail

GDBUS=${WINTIX_GDBUS:-gdbus}
JQ=${WINTIX_JQ:-jq}
STRUCTURE_SCRIPT=${WINTIX_PLASMA_STRUCTURE_SCRIPT:-@structureScript@}
ORDER_SCRIPT=${WINTIX_PLASMA_ORDER_SCRIPT:-@orderScript@}
SETTINGS_SCRIPT=${WINTIX_PLASMA_SETTINGS_SCRIPT:-@settingsScript@}

skip() {
  printf 'Wintix Plasma reconciliation skipped: no live Plasma session.\n'
  exit 0
}

command -v "$GDBUS" >/dev/null 2>&1 || skip
command -v "$JQ" >/dev/null 2>&1 || skip
[[ -n ${DBUS_SESSION_BUS_ADDRESS:-} ]] || skip

if ! owner=$($GDBUS call --session \
  --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
  --method org.freedesktop.DBus.NameHasOwner org.kde.plasmashell 2>/dev/null); then
  skip
fi
[[ $owner == *true* ]] || skip

evaluate() {
  local phase=$1 script=$2 script_arg output result
  if ! script_arg=$($JQ -Rs . < "$script"); then
    printf 'wintix-plasma-reconcile: could not serialize %s phase script.\n' "$phase" >&2
    return 1
  fi
  if ! output=$("$GDBUS" call --session --dest org.kde.plasmashell \
    --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript \
    "$script_arg"); then
    printf 'wintix-plasma-reconcile: %s phase failed.\n' "$phase" >&2
    return 1
  fi

  # gdbus prints the single returned string as a GVariant tuple. Plasma's
  # print() may append a newline, represented here as the two characters \n.
  if [[ $output != "('"*"',)" ]]; then
    printf 'wintix-plasma-reconcile: %s phase returned an invalid response: %s\n' "$phase" "$output" >&2
    return 1
  fi
  result=${output#\(\'}
  result=${result%\',\)}
  [[ $result == *'\n' ]] && result=${result%\\n}

  case $result in
    changed|unchanged)
      printf '%s\n' "$result"
      ;;
    WINTIX_ERROR:*)
      printf 'wintix-plasma-reconcile: %s phase failed: %s\n' "$phase" "$result" >&2
      return 1
      ;;
    *)
      printf 'wintix-plasma-reconcile: %s phase returned an invalid result: %s\n' "$phase" "$result" >&2
      return 1
      ;;
  esac
}

structure_result=$(evaluate structural "$STRUCTURE_SCRIPT") || exit 1
order_result=$(evaluate order "$ORDER_SCRIPT") || exit 1
evaluate settings "$SETTINGS_SCRIPT" >/dev/null || exit 1
if [[ $structure_result == changed || $order_result == changed ]]; then
  printf 'Wintix Plasma panel structure updated; log out or reboot to apply the final panel order.\n'
else
  printf 'Wintix Plasma reconciliation complete.\n'
fi
