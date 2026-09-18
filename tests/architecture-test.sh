#!/usr/bin/env bash
set -euo pipefail

repo_root="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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

for profile in home/january/default.nix home/ksledz/default.nix; do
  grep -q '../shared/development.nix' "$profile" \
    || fail "$profile must import shared development tools"
  grep -q '../shared/dolphin.nix' "$profile" \
    || fail "$profile must import shared Dolphin configuration"
  grep -q '../shared/plasma.nix' "$profile" \
    || fail "$profile must import shared Plasma configuration"
  grep -q '../shared/git-ssh.nix' "$profile" \
    || fail "$profile must import shared Git/SSH configuration"
  grep -q '../shared/zsh.nix' "$profile" \
    || fail "$profile must import shared zsh configuration"
  if grep -q 'initExtra' "$profile"; then
    fail "$profile must not define host-specific zsh initExtra"
  fi
done

# Shared development tools belong in Home Manager, not host modules.
for host in hosts/desktop/default.nix hosts/work-laptop/default.nix; do
  if grep -q 'nodejs_24' "$host"; then
    fail "$host must not define shared Node.js tooling"
  fi
  if grep -q 'python3' "$host"; then
    fail "$host must not define shared Python tooling"
  fi
done
grep -q 'pkgs.nodejs_24' home/shared/development.nix \
  || fail "shared development module must provide Node.js 24"
grep -q 'pkgs.python3' home/shared/development.nix \
  || fail "shared development module must provide Python 3"
grep -q 'programs.vscode' home/shared/development.nix \
  || fail "shared development module must provide VS Code"

# Private and machine-local Zsh helpers are connected through an optional,
# conventional path rather than referenced from outside the flake.
grep -q '\$HOME/.config/zsh/local.zsh' home/shared/zsh.nix \
  || fail "shared zsh configuration must source the optional local extension"

# Work-only applications and launchers stay in the work profile.
for app in thunderbird obsidian slack; do
  grep -qi "$app" home/ksledz/work-apps.nix \
    || fail "work app list must include $app"
  if grep -qi "$app" home/january/default.nix; then
    fail "desktop profile must not contain work app $app"
  fi
done
for launcher in thunderbird md.obsidian.Obsidian slack code; do
  grep -q "$launcher" home/ksledz/work-apps.nix \
    || fail "work launcher list must include $launcher"
done

# Shared launchers remain in the shared Plasma module. Detailed panel/reconcile
# behavior is covered by the dedicated plasma-panel flake check.
for launcher in brave dolphin konsole; do
  grep -q "$launcher" home/shared/plasma.nix \
    || fail "shared Plasma launchers must include $launcher"
done
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

# Huawei HDC USB access is required only by work-laptop development tooling.
for usb_id in 12d1 5000; do
  grep -q "$usb_id" hosts/work-laptop/default.nix \
    || fail "work-laptop must grant access to Huawei HDC USB devices"
  if grep -q "$usb_id" hosts/desktop/default.nix modules/*.nix; then
    fail "Huawei HDC USB access must remain scoped to work-laptop"
  fi
done

# Battery charge controls are hardware-specific and must remain on work-laptop.
grep -q './battery-charge.nix' hosts/work-laptop/default.nix \
  || fail "work-laptop must import its battery charge module"
for item in wintix-charge-care wintix-charge-full wintix-battery-charge-care; do
  grep -q "$item" hosts/work-laptop/battery-charge.nix \
    || fail "work-laptop battery module must define $item"
  if grep -q "$item" hosts/desktop/default.nix modules/*.nix; then
    fail "$item must not leak into desktop or shared modules"
  fi
done

echo "architecture-test: ok"
