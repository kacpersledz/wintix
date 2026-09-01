#!/usr/bin/env bash

prepare_checkout() {
  local checkout="$MOUNT_POINT/home/$USERNAME/.wintix"
  mkdir -p "$MOUNT_POINT/home/$USERNAME"
  git clone "$WINTIX_REPOSITORY" "$checkout"
  write_storage_config "$checkout"
  # Disko owns filesystem and LUKS declarations.  This only refreshes hardware
  # detection for the actual machine being installed.
  nixos-generate-config --root "$MOUNT_POINT" --no-filesystems
  local generated="$MOUNT_POINT/etc/nixos/hardware-configuration.nix"
  [[ -f $generated ]] && cp "$generated" "$checkout/hosts/$SELECTED_HOST/hardware-configuration.nix"
  printf '%s' "$checkout"
}

install_system() {
  local checkout=$1 password=$2 hash
  # Password data never enters arguments, logs, or the generated checkout.
  hash=$(printf '%s' "$password" | openssl passwd -6 -stdin)
  nixos-install --root "$MOUNT_POINT" --flake "$checkout#$SELECTED_HOST" --no-root-passwd
  printf '%s:%s\n' "$USERNAME" "$hash" | nixos-enter --root "$MOUNT_POINT" -- chpasswd -e
  nixos-enter --root "$MOUNT_POINT" -- chown -R "$USERNAME:users" "/home/$USERNAME/.wintix"
}
