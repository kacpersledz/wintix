#!/usr/bin/env bash

readonly MIN_BYTES=$((80 * 1024 * 1024 * 1024))
readonly MIN_ESP_BYTES=$((2 * 1024 * 1024 * 1024))

part_path() { [[ $1 =~ (nvme|mmcblk|loop) ]] && printf '%sp%s' "$1" "$2" || printf '%s%s' "$1" "$2"; }

live_disks() {
  # Walk each mounted source back to its parent disk. This excludes ISO, USB,
  # and any other disk currently serving the live environment.
  findmnt -rn -o SOURCE | while read -r source; do
    [[ -b $source ]] || continue
    if [[ $(lsblk -ndo TYPE "$source" 2>/dev/null) == loop ]]; then
      # Installer ISOs are normally loop-mounted from a file on the USB disk.
      # Resolve that backing file once more to identify the physical parent.
      source=$(losetup -no BACK-FILE "$source" 2>/dev/null || true)
      source=$(findmnt -T "$source" -no SOURCE 2>/dev/null || true)
    fi
    [[ -b $source ]] || continue
    local parent
    parent=$(lsblk -ndo PKNAME "$source" 2>/dev/null | head -n1)
    [[ -n $parent ]] && printf '/dev/%s\n' "$parent" || \
      [[ $(lsblk -ndo TYPE "$source" 2>/dev/null) == disk ]] && printf '%s\n' "$source"
  done | sort -u
}

is_live_disk() { live_disks | grep -Fxq "$1"; }

gpt_disk() { [[ $(sfdisk --json "$1" | jq -r '.partitiontable.label // empty') == gpt ]]; }

disk_snapshot() {
  local disk=$1
  sfdisk --json "$disk" | jq -c --arg disk "$disk" '{disk:$disk, table:.partitiontable.label, id:.partitiontable.id, size:(.partitiontable.sectors // 0), partitions:[.partitiontable.partitions[]? | {node,start,size,type,uuid,name}]}'
}

select_disk() {
  local options=() disk size model
  while read -r disk; do
    is_live_disk "$disk" && continue
    size=$(lsblk -dno SIZE "$disk")
    model=$(lsblk -dno MODEL "$disk" | xargs)
    options+=("$disk | $size | ${model:-unknown model}")
  done < <(lsblk -dpno NAME,TYPE | awk '$2 == "disk" {print $1}')
  ((${#options[@]})) || die "No non-live physical disks were found."
  SELECTED_DISK=$(gum choose --header "Select installation disk" "${options[@]}" | cut -d' ' -f1)
  gpt_disk "$SELECTED_DISK" || die "$SELECTED_DISK is not GPT. Choose whole-disk after manually preparing it, or use a GPT disk."
  DISK_REVIEW_SNAPSHOT=$(disk_snapshot "$SELECTED_DISK")
}

show_disk() { lsblk -o NAME,PATH,SIZE,MODEL,PTTYPE,PARTTYPE,FSTYPE,LABEL,MOUNTPOINTS "$1"; }

esp_candidates() {
  local disk=$1
  lsblk -J -b -o PATH,PARTTYPE,FSTYPE,SIZE "$disk" | jq -r --argjson min "$MIN_ESP_BYTES" '
    .. | objects | select(.parttype? == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" and (.fstype == "vfat" or .fstype == "fat" or .fstype == "fat32") and (.size >= $min)) | .path'
}

select_esp() {
  local list=() esp
  while read -r esp; do [[ -n $esp ]] && list+=("$esp ($(lsblk -bno SIZE "$esp" | numfmt --to=iec))"); done < <(esp_candidates "$1")
  ((${#list[@]})) || die "No GPT FAT ESP of at least 2 GiB exists. Prepare one manually or use whole-disk installation."
  ESP_PARTITION=$(gum choose --header "Reuse EFI System Partition (never formatted)" "${list[@]}" | cut -d' ' -f1)
}

# Emit aligned real gaps as: start-sector end-sector size-bytes.  Partition
# occupancy is sorted; gaps are never calculated by summing free sectors.
free_regions() {
  local disk=$1 sectors ss
  sectors=$(blockdev --getsz "$disk")
  ss=$(blockdev --getss "$disk")
  sfdisk --json "$disk" | jq -r '.partitiontable.partitions[]? | [.start,.size] | @tsv' | sort -n | \
    awk -v total="$sectors" -v ss="$ss" -v min="$MIN_BYTES" '
      function emit(a,b, start,end,bytes) { start=int((a+2047)/2048)*2048; end=int(b/2048)*2048-1; bytes=(end-start+1)*ss; if (end>=start && bytes>=min) print start "\t" end "\t" bytes }
      BEGIN { previous=2048 }
      { emit(previous, $1-1); if ($1+$2>previous) previous=$1+$2 }
      END { emit(previous, total-34) }'
}

select_free_region() {
  local options=() line start end bytes
  while IFS=$'\t' read -r start end bytes; do
    options+=("$start:$end ($(numfmt --to=iec "$bytes"))")
  done < <(free_regions "$SELECTED_DISK")
  ((${#options[@]})) || die "No contiguous unallocated region of at least 80 GiB exists; no partitions were changed."
  local choice; choice=$(gum choose --header "Select contiguous unallocated region" "${options[@]}")
  FREE_START=${choice%%:*}; FREE_END=${choice%% *}
}

select_replace_partition() {
  local options=() path size fstype parttype
  while IFS=$'\t' read -r path size fstype parttype; do
    [[ $parttype == c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] && continue
    ((size >= MIN_BYTES)) || continue
    options+=("$path | $(numfmt --to=iec "$size") | ${fstype:-unformatted} | ${parttype:-Linux/unknown}")
  done < <(lsblk -J -b -o PATH,SIZE,FSTYPE,PARTTYPE "$SELECTED_DISK" | jq -r '.. | objects | select(.type? == "part") | [.path,.size,.fstype,.parttype] | @tsv')
  ((${#options[@]})) || die "No non-ESP partition of at least 80 GiB is available."
  TARGET_PARTITION=$(gum choose --header "Select partition to replace (contents erased; GPT entry retained)" "${options[@]}" | cut -d' ' -f1)
}

assert_review_unchanged() {
  [[ $(disk_snapshot "$SELECTED_DISK") == "$DISK_REVIEW_SNAPSHOT" ]] || die "Disk partition table changed since review; stopping safely."
  is_live_disk "$SELECTED_DISK" && die "Selected disk is now used by the live environment."
  [[ ${TARGET_PARTITION:-} == "" || -b $TARGET_PARTITION ]] || die "Selected target partition disappeared."
}
