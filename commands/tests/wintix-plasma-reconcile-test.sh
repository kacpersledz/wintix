#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fake="$tmp/gdbus"; log="$tmp/log"; : >"$tmp/a.js"; : >"$tmp/b.js"
cat >"$fake" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_LOG"
if [[ $* == *NameHasOwner* ]]; then
  [[ ${MODE:-ok} == no-owner ]] && { printf '(false,)\n'; exit 0; }
  [[ ${MODE:-ok} == no-bus ]] && exit 1
  printf '(true,)\n'; exit 0
fi
count=$(grep -c evaluateScript "$FAKE_LOG")
[[ ${MODE:-ok} == structure-fail && $count == 1 ]] && exit 2
[[ ${MODE:-ok} == settings-fail && $count == 2 ]] && exit 2
[[ ${MODE:-ok} == script-error ]] && { printf "('WINTIX_ERROR: Error: verification failed',)\n"; exit 0; }
[[ ${MODE:-ok} == changed && $count == 1 ]] && { printf "('changed',)\n"; exit 0; }
printf "('unchanged',)\n"
FAKE
chmod +x "$fake"
run(){ : >"$log"; set +e; DBUS_SESSION_BUS_ADDRESS=x FAKE_LOG="$log" MODE="$1" WINTIX_GDBUS="$fake" WINTIX_PLASMA_STRUCTURE_SCRIPT="$tmp/a.js" WINTIX_PLASMA_SETTINGS_SCRIPT="$tmp/b.js" bash "$root/commands/wintix-plasma-reconcile.sh" >"$tmp/out" 2>"$tmp/err"; rc=$?; set -e; }
run no-owner; [[ $rc == 0 ]]; grep -q 'skipped: no live Plasma session' "$tmp/out"; ! grep -q evaluateScript "$log"
run no-bus; [[ $rc == 0 ]]
run ok; [[ $rc == 0 ]]; grep -q 'reconciliation complete' "$tmp/out"; [[ $(grep -c evaluateScript "$log") == 2 ]]; grep -q -- '--dest org.kde.plasmashell --object-path /PlasmaShell --method org.kde.PlasmaShell.evaluateScript' "$log"
run changed; [[ $rc == 0 ]]; grep -q 'log out or reboot' "$tmp/out"
run structure-fail; [[ $rc != 0 ]]; [[ $(grep -c evaluateScript "$log") == 1 ]]
run settings-fail; [[ $rc != 0 ]]; [[ $(grep -c evaluateScript "$log") == 2 ]]
run script-error; [[ $rc != 0 ]]; [[ $(grep -c evaluateScript "$log") == 1 ]]
printf 'wintix-plasma-reconcile tests passed\n'
