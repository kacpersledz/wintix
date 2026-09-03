#!/usr/bin/env bash

prepare_checkout() {
  local checkout="$MOUNT_POINT/home/$USERNAME/.wintix"
  mkdir -p "$MOUNT_POINT/home/$USERNAME"
  git clone "$WINTIX_GIT_URL" "$checkout"
  write_storage_config "$checkout"
  configure_checkout_git "$checkout"
  # Disko owns filesystem and LUKS declarations.  This only refreshes hardware
  # detection for the actual machine being installed.
  update_hardware_configuration "$checkout"
}

configure_checkout_git() {
  local checkout=$1
  git -C "$checkout" remote set-url origin "$WINTIX_ORIGIN_URL"
  # This tracked local override is consumed by Git-backed flakes, while its
  # machine-specific identifiers stay out of routine status and commits.
  git -C "$checkout" update-index --skip-worktree modules/storage-generated.nix
}

report_checkout_status() {
  local checkout=$1 status
  status=$(git -C "$checkout" status --porcelain --untracked-files=all)
  if [[ -z $status ]]; then
    success "Installation complete. Editable checkout is clean: /home/$USERNAME/.wintix"
  elif [[ ${HARDWARE_CONFIG_CHANGED:-0} == 1 ]]; then
    warn "Installation complete with visible checkout changes. Review them after boot with: cd ~/.wintix && git status --short && git diff"
  else
    warn "Installation complete, but the editable checkout contains unexpected visible changes. Review them after boot with: cd ~/.wintix && git status --short && git diff"
  fi
}

nix_expressions_equal() {
  local first=$1 second=$2 first_parsed second_parsed result
  first_parsed=$(mktemp)
  second_parsed=$(mktemp)
  if ! nix-instantiate --parse "$first" >"$first_parsed" || ! nix-instantiate --parse "$second" >"$second_parsed"; then
    rm -f -- "$first_parsed" "$second_parsed"
    die "Could not parse tracked and generated hardware configurations safely."
  fi
  if cmp -s "$first_parsed" "$second_parsed"; then
    result=0
  else
    result=1
  fi
  rm -f -- "$first_parsed" "$second_parsed"
  return "$result"
}

hardware_configuration_notice() {
  warn "REAL HARDWARE CONFIGURATION DIFFERENCE DETECTED.
The generated configuration replaced hosts/$SELECTED_HOST/hardware-configuration.nix.
The checkout is intentionally left dirty so this change remains visible.
Review it after boot:
cd ~/.wintix
git diff -- hosts/$SELECTED_HOST/hardware-configuration.nix"
}

update_hardware_configuration() {
  local checkout=$1 generated_root generated tracked
  generated_root=$(mktemp -d)
  mkdir -p "$generated_root/etc/nixos"
  nixos-generate-config --root "$generated_root" --no-filesystems
  generated="$generated_root/etc/nixos/hardware-configuration.nix"
  tracked="$checkout/hosts/$SELECTED_HOST/hardware-configuration.nix"
  [[ -f $generated ]] || { rm -rf -- "$generated_root"; die "nixos-generate-config did not produce a hardware configuration."; }
  [[ -f $tracked ]] || { rm -rf -- "$generated_root"; die "Tracked host hardware configuration is missing: $tracked"; }

  if nix_expressions_equal "$tracked" "$generated"; then
    export HARDWARE_CONFIG_CHANGED=0
    info "Detected hardware configuration is semantically unchanged; kept the tracked host file untouched."
  else
    cp "$generated" "$tracked"
    export HARDWARE_CONFIG_CHANGED=1
    hardware_configuration_notice
  fi
  rm -rf -- "$generated_root"
}

install_system() {
  local checkout=$1 password=$2 hash
  # Password data never enters arguments, logs, or the generated checkout.
  hash=$(printf '%s' "$password" | openssl passwd -6 -stdin)
  nixos-install --root "$MOUNT_POINT" --flake "$checkout#$SELECTED_HOST" --no-root-passwd
  printf '%s:%s\n' "$USERNAME" "$hash" | nixos-enter --root "$MOUNT_POINT" -- chpasswd -e
  nixos-enter --root "$MOUNT_POINT" -- chown -R "$USERNAME:users" "/home/$USERNAME/.wintix"
}
