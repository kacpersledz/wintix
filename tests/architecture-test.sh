#!/usr/bin/env bash
set -euo pipefail
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$root"
grep -q 'desktop = mkWorkstation' flake.nix
grep -q 'work-laptop = mkWorkstation' flake.nix
grep -q 'users.users."january"' hosts/desktop/default.nix
grep -q 'users.users.ksledz' hosts/work-laptop/default.nix
! rg -q 'wintix-github-ssh|github-ssh-key|sops' hosts/work-laptop home/ksledz home/shared
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
grep -q 'development.nix' modules/workstation.nix
! grep -q 'development.nix' hosts/desktop/default.nix
! grep -q 'development.nix' hosts/work-laptop/default.nix
grep -q '../shared/development.nix' home/january/default.nix
grep -q '../shared/development.nix' home/ksledz/default.nix
grep -q 'virtualisation.docker.enable = true' modules/development.nix
! rg -q '"docker"' hosts
! grep -E -q 'docker-(compose|buildx)' modules/development.nix
grep -q 'package = unstablePkgs.vscode' home/shared/development.nix
grep -q 'package = unstablePkgs.codex' home/shared/development.nix
grep -q 'pkgs.nodejs_24' home/shared/development.nix
grep -q 'package = pkgs.corretto21' home/shared/development.nix
! grep -q 'codex' modules/development.nix
grep -q 'by-partuuid/installer-generated' hosts/desktop/default.nix
grep -q 'by-uuid/installer-generated' hosts/desktop/default.nix
! rg -q 'by-(part)?uuid/[0-9a-fA-F]{4,}' hosts
grep -q 'gitdir:~/.wintix/' home/ksledz/default.nix
grep -q 'gitdir:~/Documents/Code/personal/' home/ksledz/default.nix
grep -q 'gitdir:~/Documents/Code/work/' home/ksledz/default.nix
grep -q 'wintix.swapSizeMiB' installer/install-system.sh
grep -q 'RAM detected:' installer/configurator.sh
grep -q 'Disk swap:' installer/configurator.sh
grep -q 'swap_and_headroom' installer/configurator.sh
grep -q 'MIN_TARGET_BYTES' installer/disk.sh
grep -q 'Minimum target size:' installer/configurator.sh
! grep -q 'readonly MIN_BYTES' installer/disk.sh
test -f home/ksledz/work-apps.nix
grep -q './work-apps.nix' home/ksledz/default.nix
grep -q 'programs.thunderbird.enable = true' home/ksledz/work-apps.nix
grep -q 'pkgs.obsidian' home/ksledz/work-apps.nix
! grep -q 'programs.obsidian' home/ksledz/work-apps.nix
grep -q 'unstablePkgs.slack' home/ksledz/work-apps.nix
grep -q 'networkmanager-openvpn' hosts/work-laptop/default.nix
! rg -q 'thunderbird|obsidian|slack' home/january hosts/desktop
! grep -q 'networkmanager-openvpn' hosts/desktop/default.nix
printf 'architecture tests passed\n'
