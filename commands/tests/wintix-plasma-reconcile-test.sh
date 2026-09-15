#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fake_gdbus="$tmp/gdbus"; fake_jq="$tmp/jq"; log="$tmp/log"
printf '%s\n' '{"launchers":["applications:brave-browser.desktop","applications:org.kde.dolphin.desktop","applications:org.kde.konsole.desktop"]}' >"$tmp/launchers.json"

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
if [[ $1 == -ce ]]; then
  exec node -e '
    const fs = require("node:fs");
    const value = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const ids = value.launchers;
    if (!Array.isArray(ids) || !ids.length || new Set(ids).size !== ids.length ||
        !ids.every(id => typeof id === "string" && /^applications:[^/\s]+\.desktop$/.test(id))) process.exit(1);
    process.stdout.write(JSON.stringify(ids) + "\n");
  ' "${@: -1}"
fi
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
ACTUAL_ARG=$actual EXPECTED_FILE=$expected COUNT=$count node -e '
  const fs = require("node:fs");
  const assert = require("node:assert/strict");
  const expected = fs.readFileSync(process.env.EXPECTED_FILE, "utf8");
  assert.equal(JSON.parse(process.env.ACTUAL_ARG), process.env.COUNT === "3"
    ? `const wintixLaunchers = ${JSON.stringify(JSON.parse(fs.readFileSync(process.env.WINTIX_PLASMA_LAUNCHERS_CONFIG, "utf8")).launchers)};\n${expected}`
    : expected);
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

# The guard sees the kernel effective UID, not a caller-controlled EUID
# environment value, and rejects root before inspecting the session.
: >"$log"
if unshare --user --map-root-user -- true >/dev/null 2>&1; then
  root_command=(unshare --user --map-root-user -- env EUID=1000)
else
  printf 'id() { printf "0\\n"; }\n' >"$tmp/root-bash-env"
  root_command=(env EUID=1000 BASH_ENV="$tmp/root-bash-env")
fi
set +e
"${root_command[@]}" DBUS_SESSION_BUS_ADDRESS=x FAKE_LOG="$log" WINTIX_GDBUS="$fake_gdbus" WINTIX_JQ="$fake_jq" \
  bash "$root/commands/wintix-plasma-reconcile.sh" >"$tmp/root-out" 2>"$tmp/root-err"
root_rc=$?
set -e
(( root_rc != 0 ))
grep -F 'run this command as your normal user' "$tmp/root-err" >/dev/null
[[ ! -s $log ]]

run() {
  : >"$log"
  set +e
  DBUS_SESSION_BUS_ADDRESS=x FAKE_LOG="$log" MODE="$1" \
    STRUCTURE_SCRIPT="$tmp/structure.js" ORDER_SCRIPT="$tmp/order.js" SETTINGS_SCRIPT="$tmp/settings.js" \
    WINTIX_GDBUS="$fake_gdbus" WINTIX_JQ="$fake_jq" \
    WINTIX_PLASMA_STRUCTURE_SCRIPT="$tmp/structure.js" \
    WINTIX_PLASMA_ORDER_SCRIPT="$tmp/order.js" \
    WINTIX_PLASMA_SETTINGS_SCRIPT="$tmp/settings.js" \
    WINTIX_PLASMA_LAUNCHERS_CONFIG="$tmp/launchers.json" \
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
printf '%s\n' '{"launchers":["applications:bad.desktop",42]}' >"$tmp/launchers.json"
run ok; [[ $rc != 0 ]]; grep -q 'malformed launcher config' "$tmp/err"; ! grep -q '^evaluate ' "$log"
rm "$tmp/launchers.json"
run ok; [[ $rc != 0 ]]; grep -q 'launcher config is missing' "$tmp/err"; ! grep -q '^evaluate ' "$log"
printf 'wintix-plasma-reconcile tests passed\n'
