#!/usr/bin/env bash

prepare_checkout() {
  local checkout="$MOUNT_POINT/home/$USERNAME/.wintix"
  mkdir -p "$MOUNT_POINT/home/$USERNAME"
  git clone "$WINTIX_GIT_URL" "$checkout"
  write_storage_config "$checkout"
  write_machine_config "$checkout"
  configure_checkout_git "$checkout"
  # Disko owns filesystem and LUKS declarations.  This only refreshes hardware
  # detection for the actual machine being installed.
  write_hardware_config "$checkout"
}

configure_checkout_git() {
  local checkout=$1
  git -C "$checkout" remote set-url origin "$WINTIX_ORIGIN_URL"
  # This tracked local override is consumed by Git-backed flakes, while its
  # machine-specific identifiers stay out of routine status and commits.
  git -C "$checkout" update-index --skip-worktree modules/storage-generated.nix modules/hardware-generated.nix modules/machine-generated.nix
}

report_checkout_status() {
  local checkout=$1 status
  status=$(git -C "$checkout" status --porcelain --untracked-files=all)
  if [[ -z $status ]]; then
    success "Installation complete. Editable checkout is clean: /home/$USERNAME/.wintix"
  else
    warn "Installation complete, but the editable checkout contains unexpected visible changes. Review them after boot with: cd ~/.wintix && git status --short && git diff"
  fi
}

write_hardware_config() {
  local checkout=$1 generated_root generated
  generated_root=$(mktemp -d)
  mkdir -p "$generated_root/etc/nixos"
  nixos-generate-config --root "$generated_root" --no-filesystems
  generated="$generated_root/etc/nixos/hardware-configuration.nix"
  [[ -f $generated ]] || { rm -rf -- "$generated_root"; die "nixos-generate-config did not produce a hardware configuration."; }
  cp "$generated" "$checkout/modules/hardware-generated.nix"
  rm -rf -- "$generated_root"
}

write_machine_config() {
  local checkout=$1
  printf '{ ... }:\n{\n  networking.hostName = "%s";\n  wintix.configuration = "%s";\n  wintix.swapSizeMiB = %d;\n}\n' \
    "$HOSTNAME" "$SELECTED_HOST" "$SWAP_SIZE_MIB" > "$checkout/modules/machine-generated.nix"
}

install_system() {
  local checkout=$1 password=$2 hash
  # Password data never enters arguments, logs, or the generated checkout.
  hash=$(printf '%s' "$password" | openssl passwd -6 -stdin)
  nixos-install --root "$MOUNT_POINT" --flake "$checkout#$SELECTED_HOST" --no-root-passwd
  printf '%s:%s\n' "$USERNAME" "$hash" | nixos-enter --root "$MOUNT_POINT" -- chpasswd -e
  nixos-enter --root "$MOUNT_POINT" -- chown -R "$USERNAME:users" "/home/$USERNAME/.wintix"
}
