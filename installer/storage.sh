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
      nix run "$WINTIX_REPOSITORY#disko" -- --mode destroy,format,mount --flake "$WINTIX_REPOSITORY#wintix-whole-disk" --argstr device "$SELECTED_DISK"
      TARGET_PARTITION=$(lsblk -rpn -o PATH,TYPE,FSTYPE "$SELECTED_DISK" | awk '$2 == "part" && $3 == "crypto_LUKS" {print $1; exit}')
      [[ -n $TARGET_PARTITION ]] || die "Disko completed but its encrypted partition could not be identified."
      ESP_PARTITION=$(lsblk -rpn -o PATH,TYPE,PARTTYPE "$SELECTED_DISK" | awk '$2 == "part" && tolower($3) == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" {print $1; exit}')
      [[ -n $ESP_PARTITION ]] || die "Disko completed but its ESP could not be identified."
      ;;
    free)
      create_free_partition
      nix run "$WINTIX_REPOSITORY#disko" -- --mode format,mount --flake "$WINTIX_REPOSITORY#wintix-selected-partition" --argstr device "$TARGET_PARTITION"
      ;;
    replace)
      nix run "$WINTIX_REPOSITORY#disko" -- --mode format,mount --flake "$WINTIX_REPOSITORY#wintix-selected-partition" --argstr device "$TARGET_PARTITION"
      ;;
  esac
  mkdir -p "$MOUNT_POINT/boot"
  mountpoint -q "$MOUNT_POINT/boot" || mount "$ESP_PARTITION" "$MOUNT_POINT/boot"
}

write_storage_config() {
  local checkout=$1 partuuid efiuuid
  partuuid=$(blkid -s PARTUUID -o value "$TARGET_PARTITION")
  efiuuid=$(blkid -s UUID -o value "$ESP_PARTITION")
  [[ -n $partuuid && -n $efiuuid ]] || die "Could not resolve stable identifiers for installed storage."
  umask 077
  # Installed systems always use the non-destructive selected-partition module:
  # Disko's whole-disk path is provisioning-only, while the durable host config
  # must point at the encrypted root partition's stable PARTUUID.
  printf '{ ... }:\n{\n  wintix.storage = {\n    enable = true;\n    mode = "selected-partition";\n    device = "/dev/disk/by-partuuid/%s";\n    efiDevice = "/dev/disk/by-uuid/%s";\n  };\n}\n' "$partuuid" "$efiuuid" > "$checkout/hosts/$SELECTED_HOST/storage-generated.nix"
}
