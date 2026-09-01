#!/usr/bin/env bash

preflight() {
  [[ ${EUID} -eq 0 ]] || die "Run the installer as root."
  [[ $(uname -m) == x86_64 ]] || die "Only x86_64 is currently supported."
  [[ -d /sys/firmware/efi ]] || die "UEFI boot is required."
  [[ -e /sys/firmware/efi/efivars ]] || die "EFI variables are unavailable; boot the installer in UEFI mode."
  for command in gum jq lsblk sfdisk sgdisk blkid nix nixos-install git; do require_command "$command"; done
  curl --fail --silent --max-time 10 https://github.com >/dev/null || die "Network access to GitHub is required."
}
