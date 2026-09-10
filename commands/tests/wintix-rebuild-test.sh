#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"; printf 'desktop\n' >"$tmp/config"
for tool in sudo nixos-rebuild wintix-plasma-reconcile; do
printf '#!%s\n' "$(command -v bash)" >"$tmp/bin/$tool"
cat >>"$tmp/bin/$tool" <<'FAKE'
printf '%s\n' "$(basename "$0") $*" >>"$LOG"
case $(basename "$0") in
 sudo) shift 0; exec "$@";;
 nixos-rebuild) [[ ${REBUILD:-pass} == pass ]];;
 wintix-plasma-reconcile) [[ ${RECONCILE:-pass} == pass ]];;
esac
FAKE
chmod +x "$tmp/bin/$tool"; done
run(){ : >"$tmp/log"; set +e; PATH="$tmp/bin:$PATH" LOG="$tmp/log" REBUILD="$1" RECONCILE="$2" WINTIX_PATH="$root" WINTIX_CONFIGURATION_FILE="$tmp/config" bash "$root/commands/wintix-rebuild.sh" >/dev/null 2>"$tmp/err"; rc=$?; set -e; }
run pass pass; [[ $rc == 0 ]]; [[ $(sed -n '2p' "$tmp/log") == nixos-rebuild* ]]; [[ $(sed -n '3p' "$tmp/log") == wintix-plasma-reconcile* ]]
run fail pass; [[ $rc != 0 ]]; ! grep -q wintix-plasma-reconcile "$tmp/log"
run pass fail; [[ $rc != 0 ]]
run pass pass # a no-session helper is represented by its successful result
[[ $rc == 0 ]]
printf 'wintix-rebuild tests passed\n'
