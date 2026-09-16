#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  echo "architecture-test: $*" >&2
  exit 1
}

# Keep this test intentionally simple: it protects the repository's host/shared
# boundaries without requiring a Nix evaluator.
grep -q 'users.january = import ../../home/january/default.nix;' hosts/desktop/default.nix \
  || fail "desktop must use the january Home Manager profile"
grep -q 'home-manager.users.ksledz = import ../../home/ksledz/default.nix;' hosts/work-laptop/default.nix \
  || fail "work-laptop must use the ksledz Home Manager profile"

grep -q '../shared/development.nix' home/january/default.nix \
  || fail "desktop profile must import shared development tools"
grep -q '../shared/development.nix' home/ksledz/default.nix \
  || fail "work profile must import shared development tools"

grep -q '../shared/plasma.nix' home/january/default.nix \
  || fail "desktop profile must import shared Plasma configuration"
grep -q '../shared/plasma.nix' home/ksledz/default.nix \
  || fail "work profile must import shared Plasma configuration"

grep -q '../shared/git-ssh.nix' home/january/default.nix \
  || fail "desktop profile must import shared Git/SSH configuration"
grep -q '../shared/git-ssh.nix' home/ksledz/default.nix \
  || fail "work profile must import shared Git/SSH configuration"

for profile in home/january/default.nix home/ksledz/default.nix; do
  grep -q '../shared/zsh.nix' "$profile" \
    || fail "$profile must import shared zsh configuration"
  if grep -q 'initExtra' "$profile"; then
    fail "$profile must not define host-specific zsh initExtra"
  fi
done

if grep -q 'nodejs_24' hosts/desktop/default.nix; then
  fail "desktop host must not define shared Node.js tooling"
fi
if grep -q 'nodejs_24' hosts/work-laptop/default.nix; then
  fail "work-laptop host must not define shared Node.js tooling"
fi
if grep -q 'python3' hosts/desktop/default.nix; then
  fail "desktop host must not define shared Python tooling"
fi
if grep -q 'python3' hosts/work-laptop/default.nix; then
  fail "work-laptop host must not define shared Python tooling"
fi
grep -q 'pkgs.nodejs_24' home/shared/development.nix \
  || fail "shared development module must provide Node.js 24"
grep -q 'pkgs.python3' home/shared/development.nix \
  || fail "shared development module must provide Python 3"

for app in thunderbird obsidian slack vscode; do
  grep -q "$app" home/ksledz/work-apps.nix \
    || fail "work app list must include $app"
  if grep -q "$app" home/january/default.nix; then
    fail "desktop profile must not contain work app $app"
  fi
done

for launcher in brave dolphin konsole; do
  grep -q "$launcher" home/shared/plasma.nix \
    || fail "shared Plasma launchers must include $launcher"
done

grep -q 'workLaunchers' home/ksledz/work-apps.nix \
  || fail "work app module must define work launchers"
grep -q 'programs.plasma.panels' home/shared/plasma.nix \
  || fail "shared Plasma module must define the bottom panel declaratively"
grep -q 'org.kde.plasma.systemtray' home/shared/plasma.nix \
  || fail "shared Plasma panel must include the system tray"
grep -q 'wintix-panel-spacer' home/shared/plasma.nix \
  || fail "shared Plasma panel must use the custom spacer widget"
grep -q 'wintix-plasma-reconcile' home/shared/plasma.nix \
  || fail "shared Plasma module must provide the reconcile command"
grep -q 'plasma-org.kde.plasma.desktop-appletsrc' home/shared/plasma.nix \
  || fail "shared Plasma module must manage panel layout"
grep -q 'kscreenlockerrc' home/shared/plasma.nix \
  || fail "shared Plasma module must manage lock-screen configuration"
grep -q 'kdeglobals' home/shared/plasma.nix \
  || fail "shared Plasma module must manage KDE globals"
grep -q 'kwinrc' home/shared/plasma.nix \
  || fail "shared Plasma module must manage KWin configuration"

if grep -q 'programs.plasma.panels' home/ksledz/work-apps.nix; then
  fail "work app module must not redefine the shared Plasma panel"
fi
if grep -q 'wintix-plasma-reconcile' home/ksledz/work-apps.nix; then
  fail "work app module must not redefine the shared reconcile command"
fi

# Smart-card support is intentionally host-scoped to the work laptop.
grep -q 'services.pcscd.enable = true;' hosts/work-laptop/default.nix \
  || fail "work-laptop must enable pcscd"
grep -q 'pkgs.pcsc-tools' hosts/work-laptop/default.nix \
  || fail "work-laptop must provide pcsc-tools"
if grep -q 'services.pcscd.enable = true;' hosts/desktop/default.nix; then
  fail "desktop must not enable work-laptop smart-card support"
fi
if grep -q 'services.pcscd.enable = true;' modules/workstation.nix; then
  fail "shared workstation module must not enable work-laptop smart-card support"
fi

echo "architecture-test: ok"
