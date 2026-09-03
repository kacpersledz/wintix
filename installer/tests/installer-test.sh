#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
TEST_ROOT=$(mktemp -d)
TEST_BIN="$TEST_ROOT/bin"
GUM_LOG="$TEST_ROOT/gum.log"
mkdir -p "$TEST_BIN" "$TEST_ROOT/ventoy"
touch "$TEST_ROOT/ventoy/wintix.iso"

cleanup() {
  rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT

export PATH="$TEST_BIN:$PATH"
export GUM_LOG TEST_ROOT

write_fake_commands() {
  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'last=${@: -1}' \
    'if [[ "$*" == *"NAME,TYPE"* ]]; then' \
    '  if [[ ${FAKE_LSBLK_MODE:-default} == rom ]]; then printf "%s\\n" "/dev/vda disk" "/dev/sr0 rom"; else printf "%s\\n" "/dev/sdb disk" "/dev/nvme0n1 disk"; fi' \
    'elif [[ "$*" == *"SIZE"* ]]; then' \
    '  printf "100G\\n"' \
    'elif [[ "$*" == *"MODEL"* ]]; then' \
    '  printf "target\\n"' \
    'elif [[ "$*" == *"PATH,TYPE"* && $last == /dev/nvme0n1 ]]; then' \
    '  printf "%s\\n" "${last} disk" /dev/nvme0n1p1\ part /dev/nvme0n1p2\ part /dev/nvme0n1p3\ part /dev/nvme0n1p4\ part' \
    'elif [[ "$*" == *"PATH"* ]]; then' \
    '  case $last in' \
    '    /dev/mapper/live-rw) printf "/dev/mapper/live-rw\\n/dev/md/live\\n/dev/loop0\\n" ;;' \
    '    /dev/md/live) printf "/dev/md/live\\n/dev/loop0\\n" ;;' \
    '    /dev/loop0) printf "/dev/loop0\\n" ;;' \
    '    /dev/sdb1) printf "/dev/sdb1\\n/dev/sdb\\n" ;;' \
    '    /dev/nvme0n1p1) printf "/dev/nvme0n1p1\\n/dev/nvme0n1\\n" ;;' \
    '    /dev/nvme0n1p2) printf "/dev/nvme0n1p2\\n/dev/nvme0n1\\n" ;;' \
    '    /dev/nvme0n1p3) printf "/dev/nvme0n1p3\\n/dev/nvme0n1\\n" ;;' \
    '    /dev/nvme0n1p4) printf "/dev/nvme0n1p4\\n/dev/nvme0n1\\n" ;;' \
    '    /dev/nvme0n1) printf "/dev/nvme0n1\\n" ;;' \
    '    /dev/sdb) printf "/dev/sdb\\n" ;;' \
    '    /dev/sr0) printf "/dev/sr0\\n" ;;' \
    '    /dev/vda) printf "/dev/vda\\n" ;;' \
    '    *) printf "%s\\n" "$last" ;;' \
    '  esac' \
    'else' \
    '  case $last in' \
    '    /dev/mapper/live-rw) printf "dm\\n" ;;' \
    '    /dev/md/live) printf "md\\n" ;;' \
    '    /dev/loop0) printf "loop\\n" ;;' \
    '    /dev/sdb|/dev/nvme0n1|/dev/vda) printf "disk\\n" ;;' \
    '    /dev/sr0) printf "rom\\n" ;;' \
    '    /dev/*) printf "part\\n" ;;' \
    '  esac' \
    'fi' > "$TEST_BIN/lsblk"
  chmod +x "$TEST_BIN/lsblk"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${1:-} == -no && ${2:-} == BACK-FILE ]]; then printf "%s\\n" "$TEST_ROOT/ventoy/wintix.iso"; fi' > "$TEST_BIN/losetup"
  chmod +x "$TEST_BIN/losetup"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'target=' \
    'for ((i = 1; i <= $#; i++)); do' \
    '  if [[ ${!i} == -T ]]; then j=$((i + 1)); target=${!j}; fi' \
    'done' \
    'if [[ "$*" == *"-P -o SOURCE,TARGET"* ]]; then' \
    '  if [[ ${FAKE_FINDMNT_MODE:-live} == mounts ]]; then' \
    '    printf "%s\\n" '\''SOURCE="/dev/nvme0n1p1" TARGET="/tmp/calamares-XXXX"'\''' \
    '    printf "%s\\n" '\''SOURCE="/dev/nvme0n1p1" TARGET="/run/other-mount"'\''' \
    '    printf "%s\\n" '\''SOURCE="/dev/nvme0n1p2" TARGET="/mnt/target"'\''' \
    '    printf "%s\\n" '\''SOURCE="/dev/nvme0n1p3" TARGET="/mnt/preserved"'\''' \
    '  fi' \
    '  exit 0' \
    'fi' \
    'if [[ $target == "$TEST_ROOT/ventoy/wintix.iso" ]]; then printf "/dev/sdb1\\n"; exit 0; fi' \
    'if [[ "$*" == *"OPTIONS"* ]]; then exit 0; fi' \
    'if [[ ${FAKE_FINDMNT_MODE:-live} == live ]]; then printf "/dev/mapper/live-rw\\n"; fi' \
    'if [[ ${FAKE_FINDMNT_MODE:-live} == rom ]]; then printf "/dev/sr0\\n"; fi' > "$TEST_BIN/findmnt"
  chmod +x "$TEST_BIN/findmnt"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case ${1:-} in' \
    '  style) shift; printf "%s\\n" "$*" >> "$GUM_LOG"; printf "%s\\n" "$*" ;;' \
    '  input) printf "%s\\n" "$*" >> "$GUM_LOG"; printf "ERASE\\n" ;;' \
    '  choose) printf "%s\\n" "${@: -1}" ;;' \
    '  *) exit 0 ;;' \
    'esac' > "$TEST_BIN/gum"
  chmod +x "$TEST_BIN/gum"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'root=${2:?missing --root}' \
    'mkdir -p "$root/etc/nixos"' \
    'cp "$FAKE_HW_SOURCE" "$root/etc/nixos/hardware-configuration.nix"' > "$TEST_BIN/nixos-generate-config"
  chmod +x "$TEST_BIN/nixos-generate-config"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'case $* in' \
    '  *config.wintix.storage.device) printf "%s\\n" "$FAKE_DEFAULT_DEVICE" ;;' \
    '  *config.wintix.storage.efiDevice) printf "%s\\n" "$FAKE_DEFAULT_ESP" ;;' \
    '  *) exit 90 ;;' \
    'esac' > "$TEST_BIN/nix"
  chmod +x "$TEST_BIN/nix"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    '[[ ${1:-} == --parse ]]' \
    'sed '\''s/#.*$//; /^[[:space:]]*$/d'\'' "$2" | tr -d '\''[:space:]'\''' > "$TEST_BIN/nix-instantiate"
  chmod +x "$TEST_BIN/nix-instantiate"

  printf '%s\n' '#!/usr/bin/env bash' \
    'set -euo pipefail' \
    'if [[ ${2:-} == PARTUUID ]]; then printf "%s\\n" "$FAKE_PARTUUID"; else printf "%s\\n" "$FAKE_ESP_UUID"; fi' > "$TEST_BIN/blkid"
  chmod +x "$TEST_BIN/blkid"
}

write_fake_commands
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/disk.sh"
source "$SCRIPT_DIR/configurator.sh"
source "$SCRIPT_DIR/storage.sh"
source "$SCRIPT_DIR/install-system.sh"

# The live environment is an ISO loop device on a device-mapper/md layer,
# backed by the Ventoy partition. A mounted Calamares partition is deliberately
# present in the fake system but is not consulted by live_disks.
FAKE_FINDMNT_MODE=live
export FAKE_FINDMNT_MODE
[[ $(live_disks) == /dev/sdb ]]
! is_live_disk /dev/nvme0n1
SELECTED_DISK=/dev/nvme0n1
assert_live_media_safe

# A directly mounted ISO/CD-ROM is resolved safely even though TYPE=rom is not
# itself a selectable target. The normal virtual disk remains available, and
# the pre-destructive safety check accepts it.
FAKE_FINDMNT_MODE=rom
FAKE_LSBLK_MODE=rom
export FAKE_FINDMNT_MODE FAKE_LSBLK_MODE
[[ $(live_media_devices) == $'nonselectable\t/dev/sr0' ]]
[[ -z $(live_disks) ]]
SELECTED_DISK=/dev/vda
assert_live_media_safe
disk_snapshot() { printf 'stable snapshot\n'; }
SELECTED_DISK=''
select_disk
[[ $SELECTED_DISK == /dev/vda ]]

# No resolved disk or explicitly non-selectable medium remains fail-closed.
FAKE_FINDMNT_MODE=none
FAKE_LSBLK_MODE=default
export FAKE_FINDMNT_MODE FAKE_LSBLK_MODE
SELECTED_DISK=/dev/nvme0n1
set +e
unresolved_error=$(assert_live_media_safe 2>&1)
unresolved_rc=$?
set -e
((unresolved_rc != 0))
[[ $unresolved_error == *'Could not determine which physical disk'* ]]

# The target remains selectable even though a different partition is mounted;
# only the live boot disk is filtered from the physical-disk choices.
FAKE_FINDMNT_MODE=live
export FAKE_FINDMNT_MODE
disk_snapshot() { printf 'stable snapshot\n'; }
SELECTED_DISK=''
select_disk
[[ $SELECTED_DISK == /dev/nvme0n1 ]]

# Relevant target and ESP mounts are reported and stop the operation. The
# unrelated preserved partition is not reported, and no unmount command exists
# in this test harness for the assertion to accidentally invoke.
FAKE_FINDMNT_MODE=mounts
FAKE_LSBLK_MODE=default
export FAKE_FINDMNT_MODE
INSTALL_MODE=replace
TARGET_PARTITION=/dev/nvme0n1p2
ESP_PARTITION=/dev/nvme0n1p1
set +e
mount_error=$(assert_no_relevant_mounts 2>&1)
mount_rc=$?
set -e
((mount_rc != 0))
[[ $mount_error == *'/dev/nvme0n1p1 is currently mounted at:'* ]]
[[ $mount_error == *'/tmp/calamares-XXXX'* ]]
[[ $mount_error == *'/run/other-mount'* ]]
[[ $mount_error == *'/dev/nvme0n1p2 is currently mounted at:'* ]]
[[ $mount_error == *'sudo umount /tmp/calamares-XXXX'* ]]
[[ $mount_error != *'/dev/nvme0n1p3 is currently mounted'* ]]
[[ $mount_error == *'will not unmount filesystems automatically'* ]]

# The review names exact destroyed/preserved paths, while the input prompt is
# only ERASE and never embeds a device path.
: > "$GUM_LOG"
FAKE_FINDMNT_MODE=none
export FAKE_FINDMNT_MODE
SELECTED_HOST=desktop
USERNAME=january
SELECTED_DISK=/dev/nvme0n1
INSTALL_MODE=replace
TARGET_PARTITION=/dev/nvme0n1p2
ESP_PARTITION=/dev/nvme0n1p1
review_plan
[[ $(cat "$GUM_LOG") == *'DESTROYED: /dev/nvme0n1p2'* ]]
[[ $(cat "$GUM_LOG") == *'PRESERVED: /dev/nvme0n1p1, /dev/nvme0n1p3, /dev/nvme0n1p4'* ]]
[[ $(cat "$GUM_LOG") == *'Type ERASE to continue:'* ]]
old_prompt='Type ERASE '
old_prompt+='/dev/nvme0n1'
[[ $(cat "$GUM_LOG") != *"$old_prompt"* ]]

# Whole-disk mode states that the entire selected disk is destroyed.
: > "$GUM_LOG"
INSTALL_MODE=wipe
ESP_PARTITION='generated by Disko'
review_plan
[[ $(cat "$GUM_LOG") == *'DESTROYED: ENTIRE SELECTED DISK: /dev/nvme0n1'* ]]
[[ $(cat "$GUM_LOG") == *'PRESERVED: nothing on selected disk'* ]]

# Matching host defaults leave the empty stub untouched. Different identifiers
# are retained as machine-local state hidden by skip-worktree.
storage_checkout="$TEST_ROOT/storage-checkout"
mkdir -p "$storage_checkout/modules"
printf '%s\n' '# generated storage stub' '{ ... }:' '{ }' > "$storage_checkout/modules/storage-generated.nix"
TARGET_PARTITION=/dev/nvme0n1p2
ESP_PARTITION=/dev/nvme0n1p1
FAKE_PARTUUID=part-uuid
FAKE_ESP_UUID=esp-uuid
FAKE_DEFAULT_DEVICE=/dev/disk/by-partuuid/part-uuid
FAKE_DEFAULT_ESP=/dev/disk/by-uuid/esp-uuid
export FAKE_PARTUUID FAKE_ESP_UUID FAKE_DEFAULT_DEVICE FAKE_DEFAULT_ESP
write_storage_config "$storage_checkout"
[[ $(<"$storage_checkout/modules/storage-generated.nix") == $'# generated storage stub\n{ ... }:\n{ }' ]]
FAKE_DEFAULT_DEVICE=/dev/disk/by-partuuid/other-part
export FAKE_DEFAULT_DEVICE
write_storage_config "$storage_checkout"
[[ $(<"$storage_checkout/modules/storage-generated.nix") == *'device = "/dev/disk/by-partuuid/part-uuid"'* ]]
[[ $(<"$storage_checkout/modules/storage-generated.nix") == *'efiDevice = "/dev/disk/by-uuid/esp-uuid"'* ]]
git -C "$storage_checkout" init --quiet --initial-branch=master
git -C "$storage_checkout" config user.name test
git -C "$storage_checkout" config user.email test@example.invalid
git -C "$storage_checkout" add --all
git -C "$storage_checkout" commit --quiet -m initial
git -C "$storage_checkout" remote add origin "$WINTIX_GIT_URL"
printf '\n# new machine identifier\n' >> "$storage_checkout/modules/storage-generated.nix"
configure_checkout_git "$storage_checkout"
[[ $(git -C "$storage_checkout" remote get-url origin) == "$WINTIX_ORIGIN_URL" ]]
git -C "$storage_checkout" ls-files -v modules/storage-generated.nix | grep -q '^S '
[[ -z $(git -C "$storage_checkout" status --porcelain) ]]

write_hw_fixture() {
  local path=$1 kernel=$2
  printf '%s\n' \
    '{ config, lib, pkgs, modulesPath, ... }:' \
    '{' \
    '  # generated comment and formatting are intentionally different' \
    '  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];' \
    "  boot.kernelModules = [ \"$kernel\" ];" \
    '}' > "$path"
}

write_tracked_hw_fixture() {
  printf '%s\n' \
    '# repository comment that the generator does not retain' \
    '{ config, lib, pkgs, modulesPath, ... }:' \
    '{' \
    '  imports = [' \
    '    (modulesPath + "/installer/scan/not-detected.nix")' \
    '  ];' \
    '  boot.kernelModules = [' \
    '    "kvm-amd"' \
    '  ];' \
    '}'
}

checkout="$TEST_ROOT/checkout"
mkdir -p "$checkout/hosts/desktop"
write_tracked_hw_fixture > "$checkout/hosts/desktop/hardware-configuration.nix"
git -C "$checkout" init --quiet --initial-branch=master
git -C "$checkout" config user.name test
git -C "$checkout" config user.email test@example.invalid
git -C "$checkout" add --all
git -C "$checkout" commit --quiet -m initial
tracked_before=$(git -C "$checkout" hash-object hosts/desktop/hardware-configuration.nix)

# Parse-normalized equivalence ignores the generated comment/formatting and
# leaves the tracked checkout clean.
write_hw_fixture "$TEST_ROOT/hw-equivalent" kvm-amd
FAKE_HW_SOURCE="$TEST_ROOT/hw-equivalent"
export FAKE_HW_SOURCE
update_hardware_configuration "$checkout"
[[ ${HARDWARE_CONFIG_CHANGED:-1} == 0 ]]
[[ $(git -C "$checkout" hash-object hosts/desktop/hardware-configuration.nix) == "$tracked_before" ]]
[[ -z $(git -C "$checkout" status --porcelain) ]]

# A real parsed difference replaces the tracked file and is surfaced without
# treating it as an installation failure.
write_hw_fixture "$TEST_ROOT/hw-different" kvm-intel
FAKE_HW_SOURCE="$TEST_ROOT/hw-different"
export FAKE_HW_SOURCE
hardware_output_file="$TEST_ROOT/hardware-output"
update_hardware_configuration "$checkout" >"$hardware_output_file" 2>&1
hardware_output=$(<"$hardware_output_file")
[[ ${HARDWARE_CONFIG_CHANGED:-0} == 1 ]]
[[ $(git -C "$checkout" hash-object hosts/desktop/hardware-configuration.nix) == $(git hash-object "$TEST_ROOT/hw-different") ]]
[[ $hardware_output == *'REAL HARDWARE CONFIGURATION DIFFERENCE DETECTED'* ]]
[[ $hardware_output == *'git diff -- hosts/desktop/hardware-configuration.nix'* ]]
[[ -n $(git -C "$checkout" status --porcelain) ]]

# Bootstrap cloning is anonymous; only the installed editable checkout's
# origin is changed to SSH. The flake bootstrap ref remains independent.
[[ $WINTIX_GIT_URL == https://github.com/kacpersledz/wintix.git ]]
[[ $WINTIX_ORIGIN_URL == git@github.com:kacpersledz/wintix.git ]]
[[ $WINTIX_FLAKE_REF == github:kacpersledz/wintix ]]

printf 'installer tests passed\n'
