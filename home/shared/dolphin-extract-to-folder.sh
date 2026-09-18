#!/usr/bin/env bash
set -u

notify_failure() {
  notify-send --urgency=normal "Archive extraction" "$1" || true
}

if [[ $# -ne 1 ]]; then
  notify_failure "Select exactly one ZIP archive."
  exit 2
fi

archive=$1
archive_name=${archive##*/}

if [[ ! -f $archive ]]; then
  notify_failure "The selected archive is not a local file."
  exit 2
fi

if [[ $archive_name != *.[zZ][iI][pP] ]]; then
  notify_failure "The selected file is not a ZIP archive."
  exit 2
fi

archive_stem=${archive_name%.[zZ][iI][pP]}
if [[ -z $archive_stem ]]; then
  notify_failure "The ZIP archive must have a name before its extension."
  exit 2
fi

archive_dir=${archive%/*}
if [[ $archive_dir == "$archive" ]]; then
  archive_dir=.
fi
destination=$archive_dir/$archive_stem

# Include dangling symlinks in the refusal: extraction must never reuse a path.
if [[ -e $destination || -L $destination ]]; then
  notify_failure "The destination already exists: $destination"
  exit 1
fi

if ! mkdir -- "$destination"; then
  notify_failure "Could not create the destination: $destination"
  exit 1
fi

if ark --batch --destination "$destination" -- "$archive"; then
  exit 0
else
  status=$?
  # rmdir is deliberately used instead of recursive removal: partial output
  # from a failed extraction must remain available to the user.
  rmdir -- "$destination" 2>/dev/null || true
  exit "$status"
fi
