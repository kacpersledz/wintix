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
 sudo) if [[ ${1:-} == -v ]]; then [[ ${SUDO_MODE:-pass} == pass ]]; exit; fi; exec "$@";;
 nixos-rebuild) [[ ${REBUILD:-pass} == pass ]];;
 wintix-plasma-reconcile) [[ ${RECONCILE:-pass} == pass ]];;
esac
FAKE
chmod +x "$tmp/bin/$tool"; done
run(){ : >"$tmp/log"; set +e; PATH="$tmp/bin:$PATH" LOG="$tmp/log" REBUILD="$1" RECONCILE="$2" SUDO_MODE="${3:-pass}" WINTIX_PATH="$root" WINTIX_CONFIGURATION_FILE="$tmp/config" bash "$root/commands/wintix-rebuild.sh" >/dev/null 2>"$tmp/err"; rc=$?; set -e; }

# A user namespace provides a real effective UID of zero without introducing a
# test-only production override. Even an EUID environment value cannot bypass
# the guard, and no user path is created.
if unshare --user --map-root-user -- true >/dev/null 2>&1; then
  root_command=(unshare --user --map-root-user -- env EUID=1000)
else
  printf 'id() { printf "0\\n"; }\n' >"$tmp/root-bash-env"
  root_command=(env EUID=1000 BASH_ENV="$tmp/root-bash-env")
fi
set +e
"${root_command[@]}" WINTIX_PATH="$tmp/root-home/.wintix" WINTIX_CONFIGURATION_FILE="$tmp/config" \
  bash "$root/commands/wintix-rebuild.sh" >"$tmp/root-out" 2>"$tmp/root-err"
root_rc=$?
set -e
(( root_rc != 0 ))
grep -F 'run this command as your normal user' "$tmp/root-err" >/dev/null
[[ ! -e $tmp/root-home ]]

run fail pass fail; [[ $rc != 0 ]]; grep -q 'could not validate administrator privileges' "$tmp/err"; [[ $(<"$tmp/log") == 'sudo -v' ]]
run pass pass; [[ $rc == 0 ]]; [[ $(sed -n '2p' "$tmp/log") == *nixos-rebuild*switch* ]]; [[ $(sed -n '3p' "$tmp/log") == nixos-rebuild* ]]; [[ $(sed -n '4p' "$tmp/log") == wintix-plasma-reconcile* ]]
[[ $(sed -n '1p' "$tmp/log") == 'sudo -v' ]]
[[ $(grep -c '^sudo ' "$tmp/log") == 2 ]]
! grep -q '^sudo wintix-plasma-reconcile' "$tmp/log"
run fail pass; [[ $rc != 0 ]]; ! grep -q wintix-plasma-reconcile "$tmp/log"
run pass fail; [[ $rc != 0 ]]
run pass pass # a no-session helper is represented by its successful result
[[ $rc == 0 ]]
printf 'wintix-rebuild tests passed\n'
