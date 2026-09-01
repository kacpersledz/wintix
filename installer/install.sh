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
  checkout=$(prepare_checkout)
  install_system "$checkout" "$USER_PASSWORD"
  unset USER_PASSWORD
  success "Installation complete. Editable checkout: /home/$USERNAME/.wintix"
  gum confirm "Reboot now?" && reboot
}

main "$@"
