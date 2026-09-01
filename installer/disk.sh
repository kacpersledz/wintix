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

gpt_disk() { [[ $(sfdisk --json "$1" 2>/dev/null | jq -r '.partitiontable.label // empty') == gpt ]]; }

disk_snapshot() {
  local disk=$1 json
  if json=$(sfdisk --json "$disk" 2>/dev/null); then
    jq -c --arg disk "$disk" '{disk:$disk, table:.partitiontable.label, id:.partitiontable.id, size:(.partitiontable.sectors // 0), partitions:[.partitiontable.partitions[]? | {node,start,size,type,uuid,name}]}' <<<"$json"
  else
    # Whole-disk mode also accepts blank media with no readable partition table.
    jq -cn --arg disk "$disk" --arg size "$(blockdev --getsize64 "$disk")" '{disk:$disk,table:"none",size:$size,partitions:[]}'
  fi
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
  DISK_REVIEW_SNAPSHOT=$(disk_snapshot "$SELECTED_DISK")
}

require_gpt_for_partial_mode() {
  gpt_disk "$SELECTED_DISK" || die "Partial-disk installation requires an existing GPT table. Choose whole-disk installation or prepare GPT manually."
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
free_regions_from_table() {
  local total=$1 ss=$2 alignment
  ((ss > 0)) || die "Unsupported logical sector size: $ss bytes."
  alignment=$((1048576 / ss))
  ((1048576 % ss == 0 && alignment > 0)) || die "Unsupported logical sector size: $ss bytes."
  awk -v total="$total" -v ss="$ss" -v min="$MIN_BYTES" -v alignment="$alignment" '
      function emit(a,b, start,end,bytes) { start=int((a+alignment-1)/alignment)*alignment; end=int((b+1)/alignment)*alignment-1; bytes=(end-start+1)*ss; if (end>=start && bytes>=min) print start "\t" end "\t" bytes }
      BEGIN { previous=alignment }
      { emit(previous, $1-1); if ($1+$2>previous) previous=$1+$2 }
      END { emit(previous, total-34) }'
}

free_regions() {
  local disk=$1 bytes ss total
  bytes=$(blockdev --getsize64 "$disk")
  ss=$(blockdev --getss "$disk")
  ((bytes % ss == 0)) || die "Disk size is not divisible by its logical sector size."
  total=$((bytes / ss))
  sfdisk --json "$disk" | jq -r '.partitiontable.partitions[]? | [.start,.size] | @tsv' | sort -n | free_regions_from_table "$total" "$ss"
}

select_free_region() {
  local options=() line start end bytes
  while IFS=$'\t' read -r start end bytes; do
    options+=("$start:$end ($(numfmt --to=iec "$bytes"))")
  done < <(free_regions "$SELECTED_DISK")
  ((${#options[@]})) || die "No contiguous unallocated region of at least 80 GiB exists; no partitions were changed."
  local choice; choice=$(gum choose --header "Select contiguous unallocated region" "${options[@]}")
  parse_free_range "${choice%% *}"
}

parse_free_range() {
  local range=$1
  [[ $range =~ ^[0-9]+:[0-9]+$ ]] || die "Invalid free-region selection."
  FREE_START=${range%%:*}; FREE_END=${range#*:}
  ((FREE_START < FREE_END)) || die "Invalid free-region bounds."
}

replace_candidate_rows() {
  jq -r '.. | objects | select(.type? == "part") | [.path,.size,.fstype,.parttype] | @tsv'
}

select_replace_partition() {
  local options=() path size fstype parttype
  while IFS=$'\t' read -r path size fstype parttype; do
    [[ $parttype == c12a7328-f81f-11d2-ba4b-00a0c93ec93b ]] && continue
    ((size >= MIN_BYTES)) || continue
    options+=("$path | $(numfmt --to=iec "$size") | ${fstype:-unformatted} | ${parttype:-Linux/unknown}")
  done < <(lsblk -J -b -o PATH,TYPE,SIZE,FSTYPE,PARTTYPE "$SELECTED_DISK" | replace_candidate_rows)
  ((${#options[@]})) || die "No non-ESP partition of at least 80 GiB is available."
  TARGET_PARTITION=$(gum choose --header "Select partition to replace (contents erased; GPT entry retained)" "${options[@]}" | cut -d' ' -f1)
}

assert_review_unchanged() {
  [[ $(disk_snapshot "$SELECTED_DISK") == "$DISK_REVIEW_SNAPSHOT" ]] || die "Disk partition table changed since review; stopping safely."
  is_live_disk "$SELECTED_DISK" && die "Selected disk is now used by the live environment."
  [[ ${TARGET_PARTITION:-} == "" || -b $TARGET_PARTITION ]] || die "Selected target partition disappeared."
  if [[ $INSTALL_MODE == free ]]; then
    free_regions "$SELECTED_DISK" | awk -F'\t' -v start="$FREE_START" -v end="$FREE_END" '$1 == start && $2 == end { found=1 } END { exit !found }' || die "The reviewed free region changed; stopping safely."
  fi
}
