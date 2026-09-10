#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fake_gdbus="$tmp/gdbus"; fake_jq="$tmp/jq"; log="$tmp/log"

cat >"$tmp/structure.js" <<'JS'
structure line one
"double quotes" and 'single quotes'
backslash: \\ and a final newline
JS
cat >"$tmp/order.js" <<'JS'
order line one
"double quotes" and 'single quotes'
backslash: \\ and a final newline
JS
cat >"$tmp/settings.js" <<'JS'
settings line one
"double quotes" and 'single quotes'
backslash: \\ and a final newline
JS

printf '#!%s\n' "$(command -v bash)" >"$fake_jq"
cat >>"$fake_jq" <<'FAKE_JQ'
set -euo pipefail
[[ $1 == -Rs && $2 == . && $# == 2 ]]
exec node -e 'let value=""; process.stdin.setEncoding("utf8"); process.stdin.on("data", chunk => value += chunk); process.stdin.on("end", () => process.stdout.write(JSON.stringify(value) + "\n"));'
FAKE_JQ

printf '#!%s\n' "$(command -v bash)" >"$fake_gdbus"
cat >>"$fake_gdbus" <<'FAKE_GDBUS'
set -euo pipefail
if [[ " $* " == *NameHasOwner* ]]; then
  printf 'owner argc=%s\n' "$#" >>"$FAKE_LOG"
  [[ ${MODE:-ok} == no-owner ]] && { printf '(false,)\n'; exit 0; }
  [[ ${MODE:-ok} == no-bus ]] && exit 1
  printf '(true,)\n'; exit 0
fi

count=$(( $(grep -c '^evaluate ' "$FAKE_LOG" || true) + 1 ))
printf 'evaluate %s argc=%s\n' "$count" "$#" >>"$FAKE_LOG"
case $count in
  1) expected=$STRUCTURE_SCRIPT ;;
  2) expected=$ORDER_SCRIPT ;;
  3) expected=$SETTINGS_SCRIPT ;;
  *) exit 9 ;;
esac
actual=${!#}
ACTUAL_ARG=$actual EXPECTED_FILE=$expected node -e '
  const fs = require("node:fs");
  const assert = require("node:assert/strict");
  assert.equal(JSON.parse(process.env.ACTUAL_ARG), fs.readFileSync(process.env.EXPECTED_FILE, "utf8"));
'

[[ ${MODE:-ok} == mutation-fail && $count == 1 ]] && exit 2
[[ ${MODE:-ok} == mutation-error && $count == 1 ]] && { printf "('WINTIX_ERROR: mutation rejected',)\n"; exit 0; }
[[ ${MODE:-ok} == order-fail && $count == 2 ]] && { printf '%s\n' "('WINTIX_ERROR: order rejected\\n',)"; exit 0; }
[[ ${MODE:-ok} == settings-fail && $count == 3 ]] && exit 2
[[ ${MODE:-ok} == mutation-changed && $count == 1 ]] && { printf "('changed',)\n"; exit 0; }
[[ ${MODE:-ok} == order-changed && $count == 2 ]] && { printf '%s\n' "('changed\\n',)"; exit 0; }
printf '%s\n' "('unchanged\\n',)"
FAKE_GDBUS
chmod +x "$fake_gdbus" "$fake_jq"

run() {
  : >"$log"
  set +e
  DBUS_SESSION_BUS_ADDRESS=x FAKE_LOG="$log" MODE="$1" \
    STRUCTURE_SCRIPT="$tmp/structure.js" ORDER_SCRIPT="$tmp/order.js" SETTINGS_SCRIPT="$tmp/settings.js" \
    WINTIX_GDBUS="$fake_gdbus" WINTIX_JQ="$fake_jq" \
    WINTIX_PLASMA_STRUCTURE_SCRIPT="$tmp/structure.js" \
    WINTIX_PLASMA_ORDER_SCRIPT="$tmp/order.js" \
    WINTIX_PLASMA_SETTINGS_SCRIPT="$tmp/settings.js" \
    bash "$root/commands/wintix-plasma-reconcile.sh" >"$tmp/out" 2>"$tmp/err"
  rc=$?
  set -e
}

run_no_session() {
  : >"$log"
  set +e
  env -u DBUS_SESSION_BUS_ADDRESS WINTIX_GDBUS="$fake_gdbus" WINTIX_JQ="$fake_jq" \
    bash "$root/commands/wintix-plasma-reconcile.sh" >"$tmp/out" 2>"$tmp/err"
  rc=$?
  set -e
}

run_no_session; [[ $rc == 0 ]]; grep -q 'skipped: no live Plasma session' "$tmp/out"; ! grep -q '^evaluate ' "$log"
run no-owner; [[ $rc == 0 ]]; grep -q 'skipped: no live Plasma session' "$tmp/out"; ! grep -q '^evaluate ' "$log"
run no-bus; [[ $rc == 0 ]]
run ok; [[ $rc == 0 ]]; grep -q 'reconciliation complete' "$tmp/out"; [[ $(grep -c '^evaluate ' "$log") == 3 ]]; [[ $(grep -c '^evaluate [123] argc=9$' "$log") == 3 ]]
run mutation-changed; [[ $rc == 0 ]]; grep -q 'log out or reboot' "$tmp/out"; [[ $(grep -c '^evaluate ' "$log") == 3 ]]
run order-changed; [[ $rc == 0 ]]; grep -q 'log out or reboot' "$tmp/out"; [[ $(grep -c '^evaluate ' "$log") == 3 ]]
run mutation-fail; [[ $rc != 0 ]]; [[ $(grep -c '^evaluate ' "$log") == 1 ]]
run mutation-error; [[ $rc != 0 ]]; grep -q 'mutation rejected' "$tmp/err"; [[ $(grep -c '^evaluate ' "$log") == 1 ]]
run order-fail; [[ $rc != 0 ]]; grep -q 'order rejected' "$tmp/err"; [[ $(grep -c '^evaluate ' "$log") == 2 ]]
run settings-fail; [[ $rc != 0 ]]; [[ $(grep -c '^evaluate ' "$log") == 3 ]]
printf 'wintix-plasma-reconcile tests passed\n'
