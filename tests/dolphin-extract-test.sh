#!/usr/bin/env bash
set -euo pipefail

helper=${1:-"$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/home/shared/dolphin-extract-to-folder.sh"}
test_root=$(mktemp -d)
trap 'rm -rf -- "$test_root"' EXIT

fake_bin=$test_root/bin
mkdir -p "$fake_bin"

printf '#!%s\n' "$(command -v bash)" >"$fake_bin/notify-send"
cat >>"$fake_bin/notify-send" <<'EOF'
printf '%s\0' "$@" >>"$NOTIFY_LOG"
exit "${NOTIFY_STATUS:-0}"
EOF

printf '#!%s\n' "$(command -v bash)" >"$fake_bin/ark"
cat >>"$fake_bin/ark" <<'EOF'
printf '%s\0' "$@" >>"$ARK_LOG"
if [[ ${ARK_PARTIAL:-0} == 1 ]]; then
  printf partial >"$3/partial.txt"
fi
exit "${ARK_STATUS:-0}"
EOF
chmod +x "$fake_bin/ark" "$fake_bin/notify-send"

export PATH="$fake_bin:$PATH"
export ARK_LOG=$test_root/ark.log
export NOTIFY_LOG=$test_root/notify.log

fail() {
  echo "dolphin-extract-test: $*" >&2
  exit 1
}

reset_logs() {
  : >"$ARK_LOG"
  : >"$NOTIFY_LOG"
  unset ARK_STATUS ARK_PARTIAL NOTIFY_STATUS
}

assert_ark_call() {
  local destination=$1 archive=$2
  mapfile -d '' -t args <"$ARK_LOG"
  [[ ${#args[@]} -eq 5 ]] || fail "Ark received ${#args[@]} arguments, expected 5"
  [[ ${args[0]} == --batch ]] || fail "Ark batch flag is missing"
  [[ ${args[1]} == --destination ]] || fail "Ark destination flag is missing"
  [[ ${args[2]} == "$destination" ]] || fail "wrong Ark destination: ${args[2]}"
  [[ ${args[3]} == -- ]] || fail "Ark option terminator is missing"
  [[ ${args[4]} == "$archive" ]] || fail "wrong Ark archive path: ${args[4]}"
}

run_success_case() {
  local filename=$1 expected_stem=$2 case_dir=$test_root/case-$3
  mkdir -p "$case_dir"
  local archive=$case_dir/$filename
  printf 'original archive' >"$archive"
  reset_logs
  bash "$helper" "$archive"
  [[ -d $case_dir/$expected_stem ]] || fail "destination missing for $filename"
  [[ $(<"$archive") == 'original archive' ]] || fail "source changed for $filename"
  assert_ark_call "$case_dir/$expected_stem" "$archive"
}

run_success_case 'foo.zip' 'foo' normal
run_success_case 'archive with spaces.zip' 'archive with spaces' spaces
run_success_case 'upper.ZIP' 'upper' uppercase
run_success_case 'foo.bar.zip' 'foo.bar' dots
run_success_case '-café "quote".zip' '-café "quote"' special

case_dir=$test_root/case-existing
mkdir -p "$case_dir/foo"
printf archive >"$case_dir/foo.zip"
reset_logs
if bash "$helper" "$case_dir/foo.zip"; then
  fail "existing destination should be rejected"
fi
[[ ! -s $ARK_LOG ]] || fail "Ark ran for an existing destination"
[[ -s $NOTIFY_LOG ]] || fail "existing destination did not notify"

case_dir=$test_root/case-unsupported
mkdir -p "$case_dir"
printf archive >"$case_dir/foo.tar"
reset_logs
if bash "$helper" "$case_dir/foo.tar"; then
  fail "unsupported extension should be rejected"
fi
[[ ! -s $ARK_LOG ]] || fail "Ark ran for an unsupported extension"
[[ -s $NOTIFY_LOG ]] || fail "unsupported extension did not notify"

reset_logs
export NOTIFY_STATUS=25
set +e
bash -e "$helper" "$case_dir/foo.tar"
status=$?
set -e
[[ $status -eq 2 ]] || fail "notification failure changed the intended error status"

case_dir=$test_root/case-empty-failure
mkdir -p "$case_dir"
printf archive >"$case_dir/foo.zip"
reset_logs
export ARK_STATUS=23
set +e
bash "$helper" "$case_dir/foo.zip"
status=$?
set -e
[[ $status -eq 23 ]] || fail "Ark failure status was not propagated"
[[ ! -e $case_dir/foo ]] || fail "empty destination survived Ark failure"
[[ $(<"$case_dir/foo.zip") == archive ]] || fail "source changed after Ark failure"

case_dir=$test_root/case-partial-failure
mkdir -p "$case_dir"
printf archive >"$case_dir/foo.zip"
reset_logs
export ARK_STATUS=24 ARK_PARTIAL=1
set +e
bash "$helper" "$case_dir/foo.zip"
status=$?
set -e
[[ $status -eq 24 ]] || fail "partial Ark failure status was not propagated"
[[ $(<"$case_dir/foo/partial.txt") == partial ]] || fail "partial extraction was deleted"
[[ $(<"$case_dir/foo.zip") == archive ]] || fail "source changed after partial failure"

echo "dolphin-extract-test: ok"
