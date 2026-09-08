#!/usr/bin/env bash
set -euo pipefail

root=${1:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
task_manager="$root/home/shared/plasma/task-manager.js"
system_tray="$root/home/shared/plasma/system-tray.js"
plasma_module="$root/home/shared/plasma.nix"

grep -q 'overrideConfig = false' "$plasma_module"
! rg -q 'programs\.plasma\.panels|panels[[:space:]]*=' "$root/home"
! rg -q '(applet|containment)(Id|ID)[[:space:]]*=[[:space:]]*[0-9]+' "$root/home/shared/plasma"

grep -q 'const taskManager = "org.kde.plasma.taskmanager"' "$task_manager"
grep -q 'const iconsOnlyTaskManager = "org.kde.plasma.icontasks"' "$task_manager"
grep -q 'writeConfig("groupingStrategy", 0)' "$task_manager"
grep -q 'writeConfig("separateLaunchers", false)' "$task_manager"
grep -q 'writeConfig("interactiveMute", false)' "$task_manager"

# Migration only removes the original after re-reading and verifying the index.
assigned_line=$(grep -n 'replacement.index = oldIndex' "$task_manager" | cut -d: -f1)
reread_line=$(grep -n 'const actualIndex = replacement.index' "$task_manager" | cut -d: -f1)
verified_line=$(grep -n 'if (actualIndex !== oldIndex)' "$task_manager" | cut -d: -f1)
old_removed_line=$(grep -n 'oldWidget.remove()' "$task_manager" | cut -d: -f1)
test "$assigned_line" -lt "$reread_line"
test "$reread_line" -lt "$verified_line"
test "$verified_line" -lt "$old_removed_line"

index_failure_block=$(sed -n '/if (actualIndex !== oldIndex)/,/^[[:space:]]*}/p' "$task_manager")
grep -q 'replacement.remove()' <<< "$index_failure_block"
grep -q 'continue' <<< "$index_failure_block"

unexpected_type_block=$(sed -n '/if (replacement.type !== taskManager)/,/^[[:space:]]*}/p' "$task_manager")
grep -q 'replacement.remove()' <<< "$unexpected_type_block"
grep -q 'continue' <<< "$unexpected_type_block"

expected_launchers=$(sed -n '/^const launchers = \[/,/^\];/p' "$task_manager" | tr -d '[:space:]')
test "$expected_launchers" = 'constlaunchers=["applications:brave-browser.desktop","applications:org.kde.dolphin.desktop","applications:org.kde.konsole.desktop",];'

expected_tray_items=$(sed -n '/^const alwaysShownItems = \[/,/^\];/p' "$system_tray" | tr -d '[:space:]')
test "$expected_tray_items" = 'constalwaysShownItems=["org.kde.plasma.notifications","org.kde.plasma.weather","org.kde.plasma.battery",];'
grep -q 'writeConfig("shownItems", addUnique' "$system_tray"
grep -q 'writeConfig("hiddenItems", without' "$system_tray"
grep -q 'writeConfig("extraItems", addUnique' "$system_tray"
! rg -qi 'provider|location|weatherstation|source' "$system_tray"

printf 'Plasma panel tests passed\n'
