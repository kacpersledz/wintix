#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
source "$SCRIPT_DIR/helpers.sh"
source "$SCRIPT_DIR/disk.sh"
source "$SCRIPT_DIR/storage.sh"

gaps() { free_regions_from_table "$1" "$2" | awk -F'\t' '{print $1 ":" $2}'; }

# Two 50 GiB gaps must not be combined into an eligible 100 GiB gap.
[[ -z $(printf '2048\t104857600\n209717248\t104857600\n' | gaps 419432000 512) ]]
# A later 100 GiB gap remains independently selectable.
[[ $(printf '2048\t104857600\n' | gaps 419432000 512) == '104859648:419430399' ]]
# Native-4K disks use eight times fewer logical sectors; a 1 MiB alignment is
# therefore 256 sectors, and 80 GiB is still enforced in bytes.
[[ $(printf '256\t26214400\n' | gaps 104858000 4096) == '26214656:104857855' ]]
# A gap one 4 KiB sector smaller than 80 GiB is rejected.
[[ -z $(printf '256\t20971519\n' | gaps 20971810 4096) ]]
parse_free_range '123:456'
[[ $FREE_START == 123 && $FREE_END == 456 ]]
# Candidate parsing requires TYPE and returns real partitions, not disks.
rows=$(printf '%s' '{"blockdevices":[{"name":"sda","type":"disk","children":[{"path":"/dev/sda2","type":"part","size":90000000000,"fstype":"ntfs","parttype":"8300"}]}]}' | replace_candidate_rows)
[[ $rows == $'/dev/sda2\t90000000000\tntfs\t8300' ]]
# Partition number allocation uses the first unused GPT table index, never an
# available-sector address returned by sgdisk -F.
number=$(printf '%s' '{"partitiontable":{"partitions":[{"node":"/dev/nvme0n1p1"},{"node":"/dev/nvme0n1p3"}]}}' | first_free_partition_number)
[[ $number == 2 ]]
echo 'free-regions tests passed'
