#!/usr/bin/env bash

set -eEuo pipefail
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/preflight.sh"
source "$SCRIPT_DIR/disk.sh"
source "$SCRIPT_DIR/configurator.sh"
source "$SCRIPT_DIR/storage.sh"
source "$SCRIPT_DIR/install-system.sh"

main() {
  gum style --border double --padding "1 3" --bold "Wintix installer"
  preflight
  select_host
  select_disk
  show_disk "$SELECTED_DISK"
  select_mode
  review_plan
  assert_review_unchanged
  LUKS_NOTICE=$(gum confirm "Disko will next ask separately for a new LUKS passphrase. Continue?" && echo yes || true)
  [[ $LUKS_NOTICE == yes ]] || die "Installation cancelled before destructive provisioning."
  USER_PASSWORD=$(read_password "Password for $USERNAME")
  provision_storage
  prepare_checkout
  checkout="$MOUNT_POINT/home/$USERNAME/.wintix"
  install_system "$checkout" "$USER_PASSWORD"
  unset USER_PASSWORD
  if [[ ${HARDWARE_CONFIG_CHANGED:-0} == 1 ]]; then
    warn "Installation complete with an intentional hardware configuration change in the editable checkout. Review it after boot with: cd ~/.wintix && git diff -- hosts/$SELECTED_HOST/hardware-configuration.nix"
  else
    success "Installation complete with a semantically unchanged hardware configuration. Editable checkout is clean: /home/$USERNAME/.wintix"
  fi
  gum confirm "Reboot now?" && reboot
}

main "$@"
