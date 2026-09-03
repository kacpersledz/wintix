#!/usr/bin/env bash

create_free_partition() {
  local number parent start end
  ((FREE_START < FREE_END)) || die "Invalid reviewed free-region bounds."
  number=$(sfdisk --json "$SELECTED_DISK" | first_free_partition_number)
  [[ $number =~ ^[0-9]+$ ]] || die "No free GPT partition-table slot is available."
  info "Creating one Linux partition in the reviewed free region."
  sgdisk --new="${number}:${FREE_START}:${FREE_END}" --typecode="${number}:8300" --change-name="${number}:Wintix" "$SELECTED_DISK"
  partprobe "$SELECTED_DISK"
  udevadm settle
  TARGET_PARTITION=$(part_path "$SELECTED_DISK" "$number")
  [[ -b $TARGET_PARTITION ]] || die "New partition did not appear; stopping safely."
  parent=$(lsblk -ndo PKNAME "$TARGET_PARTITION")
  [[ /dev/$parent == "$SELECTED_DISK" ]] || die "New partition parent does not match the selected disk."
  read -r start end < <(sfdisk --json "$SELECTED_DISK" | jq -r --arg node "$TARGET_PARTITION" '.partitiontable.partitions[] | select(.node == $node) | "\(.start) \(.start + .size - 1)"')
  [[ $start == "$FREE_START" && $end == "$FREE_END" ]] || die "New partition does not match the reviewed free region."
}

first_free_partition_number() {
  jq -r '[.partitiontable.partitions[]?.node | capture("(?<number>[0-9]+)$").number | tonumber] as $used | first(range(1; 129) | select(. as $n | ($used | index($n) | not)))'
}

provision_storage() {
  assert_review_unchanged
  case $INSTALL_MODE in
    wipe)
      assert_live_media_safe
      assert_no_relevant_mounts
      nix run "$WINTIX_FLAKE_REF#disko" -- --mode destroy,format,mount --flake "$WINTIX_FLAKE_REF#wintix-whole-disk" --argstr device "$SELECTED_DISK"
      TARGET_PARTITION=$(lsblk -rpn -o PATH,TYPE,FSTYPE "$SELECTED_DISK" | awk '$2 == "part" && $3 == "crypto_LUKS" {print $1; exit}')
      [[ -n $TARGET_PARTITION ]] || die "Disko completed but its encrypted partition could not be identified."
      ESP_PARTITION=$(lsblk -rpn -o PATH,TYPE,PARTTYPE "$SELECTED_DISK" | awk '$2 == "part" && tolower($3) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1; exit}')
      [[ -n $ESP_PARTITION ]] || die "Disko completed but its ESP could not be identified."
      ;;
    free)
      assert_live_media_safe
      assert_no_relevant_mounts
      create_free_partition
      assert_live_media_safe
      assert_no_relevant_mounts
      nix run "$WINTIX_FLAKE_REF#disko" -- --mode format,mount --flake "$WINTIX_FLAKE_REF#wintix-selected-partition" --argstr device "$TARGET_PARTITION"
      ;;
    replace)
      assert_live_media_safe
      assert_no_relevant_mounts
      nix run "$WINTIX_FLAKE_REF#disko" -- --mode format,mount --flake "$WINTIX_FLAKE_REF#wintix-selected-partition" --argstr device "$TARGET_PARTITION"
      ;;
  esac
  mkdir -p "$MOUNT_POINT/boot"
  if mountpoint -q "$MOUNT_POINT/boot"; then
    local boot_options boot_source
    boot_source=$(findmnt -T "$MOUNT_POINT/boot" -rn --raw -o SOURCE 2>/dev/null | head -n1 || true)
    boot_source=${boot_source%%[*}
    [[ -n $boot_source && $(canonical_block_device "$boot_source") == $(canonical_block_device "$ESP_PARTITION") ]] || \
      die "The installer ESP mount at $MOUNT_POINT/boot is not the selected ESP ($ESP_PARTITION). Unmount it and retry. Suggested command: sudo umount $MOUNT_POINT/boot"
    boot_options=$(findmnt -T "$MOUNT_POINT/boot" -rn --raw -o OPTIONS 2>/dev/null || true)
    [[ $boot_options == *umask=0077* || ($boot_options == *fmask=0077* && $boot_options == *dmask=0077*) ]] || \
      die "The installer ESP is already mounted at $MOUNT_POINT/boot without restrictive permissions. Unmount it and retry. Suggested command: sudo umount $MOUNT_POINT/boot"
  else
    mount -o fmask=0077,dmask=0077 "$ESP_PARTITION" "$MOUNT_POINT/boot"
  fi
}

write_storage_config() {
  local checkout=$1 partuuid efiuuid desired_device desired_efi default_device default_efi
  partuuid=$(blkid -s PARTUUID -o value "$TARGET_PARTITION")
  efiuuid=$(blkid -s UUID -o value "$ESP_PARTITION")
  [[ -n $partuuid && -n $efiuuid ]] || die "Could not resolve stable identifiers for installed storage."
  desired_device="/dev/disk/by-partuuid/$partuuid"
  desired_efi="/dev/disk/by-uuid/$efiuuid"

  # Host defaults describe the normal reinstall target for this checkout. If
  # the identifiers differ, write the machine-local generated override. The
  # checkout preparation marks this tracked file skip-worktree so routine Git
  # status does not expose expected per-install identifiers.
  default_device=$(nix eval --raw "$checkout#nixosConfigurations.${SELECTED_HOST}.config.wintix.storage.device") || \
    die "Could not evaluate the selected host's default storage device."
  default_efi=$(nix eval --raw "$checkout#nixosConfigurations.${SELECTED_HOST}.config.wintix.storage.efiDevice") || \
    die "Could not evaluate the selected host's default ESP device."
  if [[ $desired_device == "$default_device" && $desired_efi == "$default_efi" ]]; then
    info "Selected storage identifiers match the host defaults; no generated storage override is needed."
    return
  fi

  umask 077
  # Installed systems always use the non-destructive selected-partition module:
  # Disko's whole-disk path is provisioning-only, while the durable host config
  # must point at the encrypted root partition's stable PARTUUID.
  printf '{ ... }:\n{\n  wintix.storage = {\n    enable = true;\n    mode = "selected-partition";\n    device = "%s";\n    efiDevice = "%s";\n  };\n}\n' "$desired_device" "$desired_efi" > "$checkout/modules/storage-generated.nix"
}
