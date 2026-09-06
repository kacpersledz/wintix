#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
grep -q 'desktop = mkWorkstation' flake.nix
grep -q 'work-laptop = mkWorkstation' flake.nix
grep -q 'users.users."january"' hosts/desktop/default.nix
grep -q 'users.users.ksledz' hosts/work-laptop/default.nix
! grep -R -E 'wintix-github-ssh|github-ssh-key|sops' hosts/work-laptop home/ksledz home/shared
test -f modules/hardware-generated.nix
grep -q 'hardware-generated.nix' modules/workstation.nix
! find hosts -name hardware-configuration.nix | grep -q .
grep -q -- '--no-filesystems' installer/install-system.sh
grep -q 'skip-worktree.*hardware-generated.nix' installer/install-system.sh
grep -q 'Hostname:' installer/configurator.sh
grep -q 'machine-generated.nix' installer/install-system.sh
grep -q 'WINTIX_CONFIGURATION_FILE' commands/wintix-rebuild.sh
grep -q 'WINTIX_CONFIGURATION_FILE' commands/wintix-update.sh
grep -q 'size = config.wintix.swapSizeMiB' modules/workstation.nix
grep -q 'memoryPercent = 50' modules/workstation.nix
! grep -q 'swapDevices' hosts/desktop/default.nix
! grep -q 'swapDevices' hosts/work-laptop/default.nix
grep -q 'wintix.swapSizeMiB' installer/install-system.sh
grep -q 'RAM detected:' installer/configurator.sh
grep -q 'Disk swap:' installer/configurator.sh
grep -q 'swap_and_headroom' installer/configurator.sh
grep -q 'MIN_TARGET_BYTES' installer/disk.sh
grep -q 'Minimum target size:' installer/configurator.sh
! grep -q 'readonly MIN_BYTES' installer/disk.sh
printf 'architecture tests passed\n'
