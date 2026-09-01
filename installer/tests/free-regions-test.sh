#!/usr/bin/env bash
set -euo pipefail

# Pure regression test for the contiguous-gap algorithm.  It intentionally
# uses sectors rather than a loop device, so it is safe on developer machines.
gaps() {
  awk -v total="$1" -v ss=512 -v min=$((80 * 1024 * 1024 * 1024)) '
    function emit(a,b, start,end,bytes) { start=int((a+2047)/2048)*2048; end=int(b/2048)*2048-1; bytes=(end-start+1)*ss; if (end>=start && bytes>=min) print start ":" end }
    BEGIN { previous=2048 }
    { emit(previous,$1-1); if ($1+$2>previous) previous=$1+$2 }
    END { emit(previous,total-34) }'
}

# Two 50 GiB gaps must not be combined into an eligible 100 GiB gap.
[[ -z $(printf '2048\t104857600\n209717248\t104857600\n' | gaps 419432000) ]]
# A later 100 GiB gap remains independently selectable.
[[ $(printf '2048\t104857600\n' | gaps 419432000) == '104859648:419430399' ]]
echo 'free-regions tests passed'
