#!/usr/bin/env bash

readonly MIN_BYTES=$((80 * 1024 * 1024 * 1024))
readonly MIN_ESP_BYTES=$((2 * 1024 * 1024 * 1024))

part_path() { [[ $1 =~ (nvme|mmcblk|loop) ]] && printf '%sp%s' "$1" "$2" || printf '%s%s' "$1" "$2"; }

canonical_block_device() {
  local device=$1 resolved
  resolved=$(readlink -f -- "$device" 2>/dev/null || true)
  printf '%s\n' "${resolved:-$device}"
}

block_device_type() { lsblk -ndo TYPE "$1" 2>/dev/null | head -n1; }

block_device_chain() {
  local source=$1 chain
  chain=$(lsblk -s -rno PATH "$source" 2>/dev/null || true)
  if [[ -n $chain ]]; then
    printf '%s\n' "$chain"
  else
    printf '%s\n' "$source"
  fi
}

# Trace a block source through lsblk's inverse dependency tree. Loop devices
# are special: their backing file is on a mounted filesystem, so resolve that
# filesystem and continue tracing from its block source. This also handles
# device-mapper, mdraid, and other intermediate block layers without depending
# on their names or removable flags.
declare -Ag WINTIX_LIVE_TRACE_SEEN=()

trace_live_block_source() {
  local source=$1 node type canonical back_file backing_source
  [[ -n $source ]] || return 0

  while read -r node; do
    [[ -n $node ]] || continue
    canonical=$(canonical_block_device "$node")
    [[ -n ${WINTIX_LIVE_TRACE_SEEN[$canonical]+seen} ]] && continue
    WINTIX_LIVE_TRACE_SEEN[$canonical]=1
    type=$(block_device_type "$node")

    case $type in
      disk)
        printf '%s\n' "$canonical"
        ;;
      loop)
        back_file=$(losetup -no BACK-FILE "$node" 2>/dev/null || true)
        [[ -n $back_file && -e $back_file ]] || continue
        backing_source=$(findmnt -T "$back_file" -rn -o SOURCE 2>/dev/null | head -n1 || true)
        [[ -n $backing_source ]] || continue
        trace_live_block_source "${backing_source%%[*}"
        ;;
    esac
  done < <(block_device_chain "$source")
}

live_mount_source() {
  findmnt -T "$1" -rn --raw -o SOURCE 2>/dev/null | head -n1 || true
}

live_mount_options() {
  findmnt -T "$1" -rn --raw -o OPTIONS 2>/dev/null | head -n1 || true
}

live_environment_sources() {
  local path source options option overlay_path path_source token ref
  local -a paths=(/ /iso /nix/.ro-store /nix/store /run/current-system /run/booted-system /boot)

  # These are the root filesystem and its system-owned mounts. Do not inspect
  # every mount: a temporary Calamares mount must not make its disk live media.
  for path in "${paths[@]}"; do
    source=$(live_mount_source "$path")
    [[ -n $source ]] && printf '%s\n' "${source%%[*}"

    options=$(live_mount_options "$path")
    while IFS= read -r option; do
      case $option in
        lowerdir=*|upperdir=*|workdir=*)
          while IFS= read -r overlay_path; do
            [[ -n $overlay_path ]] || continue
            path_source=$(live_mount_source "$overlay_path")
            [[ -n $path_source ]] && printf '%s\n' "${path_source%%[*}"
          done < <(tr ':' '\n' <<<"${option#*=}")
          ;;
      esac
    done < <(tr ',' '\n' <<<"$options")
  done

  # Some live systems keep the root filesystem in tmpfs and identify the
  # boot/root source only in the kernel command line. Resolve those references
  # as block sources too; this is boot metadata, not a device-name heuristic.
  while read -r token; do
    case $token in
      root=*|bootdev=*)
        ref=${token#*=}
        if [[ $ref == /dev/* ]]; then
          printf '%s\n' "$ref"
        elif command -v findfs >/dev/null 2>&1; then
          findfs "$ref" 2>/dev/null || true
        fi
        ;;
    esac
  done < <(tr ' ' '\n' </proc/cmdline)
}

live_disks() {
  local source disk canonical
  local -A disks=()

  while read -r source; do
    [[ -n $source ]] || continue
    WINTIX_LIVE_TRACE_SEEN=()
    while read -r disk; do
      [[ -n $disk ]] || continue
      canonical=$(canonical_block_device "$disk")
      disks[$canonical]=1
    done < <(trace_live_block_source "$source")
  done < <(live_environment_sources)

  if ((${#disks[@]})); then
    printf '%s\n' "${!disks[@]}" | sort -u
  fi
}

is_live_disk() {
  local candidate live
  candidate=$(canonical_block_device "$1")
  while read -r live; do
    [[ $live == "$candidate" ]] && return 0
  done < <(live_disks)
  return 1
}

assert_live_media_safe() {
  local candidate live
  local -a detected=()
  mapfile -t detected < <(live_disks)
  ((${#detected[@]})) || die "Could not determine which physical disk backs the running live environment; refusing to continue."
  candidate=$(canonical_block_device "$SELECTED_DISK")
  for live in "${detected[@]}"; do
    [[ $live != "$candidate" ]] || die "Selected disk is used by the live environment; choose another disk."
  done
}

block_device_related_to() {
  local source=$1 scope=$2 node canonical type back_file backing_source
  local scope_canonical
  scope_canonical=$(canonical_block_device "$scope")
  declare -Ag WINTIX_RELATION_SEEN=()

  related() {
    local current=$1 current_canonical=$2
    [[ ${WINTIX_RELATION_SEEN[$current_canonical]+seen} ]] && return 1
    WINTIX_RELATION_SEEN[$current_canonical]=1
    [[ $current_canonical == "$scope_canonical" ]] && return 0

    while read -r node; do
      [[ -n $node ]] || continue
      canonical=$(canonical_block_device "$node")
      [[ $canonical == "$scope_canonical" ]] && return 0
      type=$(block_device_type "$node")
      if [[ $type == loop ]]; then
        back_file=$(losetup -no BACK-FILE "$node" 2>/dev/null || true)
        if [[ -n $back_file && -e $back_file ]]; then
          backing_source=$(findmnt -T "$back_file" -rn -o SOURCE 2>/dev/null | head -n1 || true)
          [[ -n $backing_source ]] && related "${backing_source%%[*}" "$(canonical_block_device "${backing_source%%[*}")" && return 0
        fi
      fi
    done < <(block_device_chain "$current")
    return 1
  }

  related "$source" "$(canonical_block_device "$source")"
}

decode_findmnt_value() {
  local value=$1
  value=${value//\\040/ }
  value=${value//\\011/$'\t'}
  value=${value//\\012/$'\n'}
  printf '%s' "$value"
}

mount_records_for_scope() {
  local scope=$1 line source mountpoint
  while IFS= read -r line; do
    [[ $line =~ ^SOURCE=\"([^\"]*)\"[[:space:]]TARGET=\"([^\"]*)\"$ ]] || continue
    source=$(decode_findmnt_value "${BASH_REMATCH[1]}")
    mountpoint=$(decode_findmnt_value "${BASH_REMATCH[2]}")
    [[ -n $source && -n $mountpoint ]] || continue
    block_device_related_to "${source%%[*}" "$scope" && printf '%s\t%s\n' "${source%%[*}" "$mountpoint"
  done < <(findmnt -n -P -o SOURCE,TARGET 2>/dev/null || true)
}

mount_records_for_exact_device() {
  local scope=$1 scope_canonical line source mountpoint source_device
  scope_canonical=$(canonical_block_device "$scope")
  while IFS= read -r line; do
    [[ $line =~ ^SOURCE=\"([^\"]*)\"[[:space:]]TARGET=\"([^\"]*)\"$ ]] || continue
    source=$(decode_findmnt_value "${BASH_REMATCH[1]}")
    mountpoint=$(decode_findmnt_value "${BASH_REMATCH[2]}")
    [[ -n $source && -n $mountpoint ]] || continue
    source_device=${source%%[*}
    [[ $(block_device_type "$source_device") ]] || continue
    [[ $(canonical_block_device "$source_device") == "$scope_canonical" ]] && printf '%s\t%s\n' "$source_device" "$mountpoint"
  done < <(findmnt -n -P -o SOURCE,TARGET 2>/dev/null || true)
}

relevant_mount_records() {
  local record
  local -A seen=()
  case $INSTALL_MODE in
    wipe)
      while IFS= read -r record; do [[ -n $record ]] && seen[$record]=1; done < <(mount_records_for_scope "$SELECTED_DISK")
      ;;
    free)
      # Existing partitions are preserved in free-space mode. Only a
      # filesystem directly on the disk or the reused ESP is relevant here.
      while IFS= read -r record; do [[ -n $record ]] && seen[$record]=1; done < <(mount_records_for_exact_device "$SELECTED_DISK")
      while IFS= read -r record; do [[ -n $record ]] && seen[$record]=1; done < <(mount_records_for_scope "$ESP_PARTITION")
      ;;
    replace)
      while IFS= read -r record; do [[ -n $record ]] && seen[$record]=1; done < <(mount_records_for_scope "$TARGET_PARTITION")
      while IFS= read -r record; do [[ -n $record ]] && seen[$record]=1; done < <(mount_records_for_scope "$ESP_PARTITION")
      ;;
  esac
  if ((${#seen[@]})); then printf '%s\n' "${!seen[@]}" | sort; fi
}

assert_no_relevant_mounts() {
  local records_file source mountpoint quoted_mountpoint message=''
  records_file=$(mktemp)
  relevant_mount_records >"$records_file"
  if [[ -s $records_file ]]; then
    while IFS=$'\t' read -r source mountpoint; do
      message+=$'\n'
      message+="$source is currently mounted at:"$'\n'
      message+="$mountpoint"$'\n\n'
      message+="Close whatever is using it and unmount it before continuing."$'\n'
      message+="Wintix will not unmount filesystems automatically."$'\n\n'
      message+="Suggested command:"$'\n'
      printf -v quoted_mountpoint '%q' "$mountpoint"
      message+="sudo umount $quoted_mountpoint"$'\n'
    done <"$records_file"
    rm -f -- "$records_file"
    die "Cannot continue because a relevant target filesystem is mounted.$message"
  fi
  rm -f -- "$records_file"
}

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
  local live
  local -a detected_live_disks=()
  mapfile -t detected_live_disks < <(live_disks)
  ((${#detected_live_disks[@]})) || die "Could not determine which physical disk backs the running live environment; refusing to show destructive targets."
  while read -r disk; do
    for live in "${detected_live_disks[@]}"; do
      [[ $(canonical_block_device "$disk") == "$live" ]] && continue 2
    done
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
  assert_live_media_safe
  [[ ${TARGET_PARTITION:-} == "" || -b $TARGET_PARTITION ]] || die "Selected target partition disappeared."
  if [[ $INSTALL_MODE == free ]]; then
    free_regions "$SELECTED_DISK" | awk -F'\t' -v start="$FREE_START" -v end="$FREE_END" '$1 == start && $2 == end { found=1 } END { exit !found }' || die "The reviewed free region changed; stopping safely."
  fi
  assert_no_relevant_mounts
}
