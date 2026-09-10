#!/usr/bin/env bash
set -euo pipefail
root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
structure="$root/commands/plasma/panel-structure.js"
settings="$root/commands/plasma/panel-settings.js"
module="$root/home/shared/plasma.nix"
grep -q 'overrideConfig = false' "$module"
! rg -q 'startup\.desktopScript|runAlways' "$module" "$root/commands/plasma"
! rg -q 'programs\.plasma\.panels|panels[[:space:]]*=' "$root/home"
! rg -q 'Widget\.index|\.index[[:space:]]*=' "$structure"
grep -q 'widgetById' "$structure"
grep -q 'writeConfig("AppletOrder"' "$structure"
grep -q 'desktopById(containmentId)' "$settings"
grep -q 'readConfig("SystrayContainmentId"' "$settings"
! grep -q 'writeConfig("extraItems"' "$settings"
! rg -qi 'provider|location|weatherstation|source' "$settings"
node --check "$structure"
node --check "$settings"
node "$root/tests/plasma-panel-runtime-test.js" "$root"
printf 'Plasma panel tests passed\n'
