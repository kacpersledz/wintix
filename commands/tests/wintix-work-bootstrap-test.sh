#!/usr/bin/env bash
set -euo pipefail
root=$(mktemp -d)
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/home"

cat > "$root/bin/ssh-keygen" <<'FAKE'
#!/bin/sh
[ -n "${BASH_VERSION:-}" ] || exec bash "$0" "$@"
set -euo pipefail
if [[ ${1:-} == -y ]]; then
  key=${3:?}
  printf 'ssh-ed25519 derived-%s\n' "${key##*/}"
  exit
fi
key=
comment=
while (($#)); do
  case $1 in
    -f) key=$2; shift 2 ;;
    -C) comment=$2; shift 2 ;;
    *) shift ;;
  esac
done
[[ -n $key ]]
printf 'private-%s\n' "${key##*/}" > "$key"
printf 'ssh-ed25519 generated-%s %s\n' "${key##*/}" "$comment" > "$key.pub"
FAKE
chmod +x "$root/bin/ssh-keygen"

# Root is rejected before prompting or creating Git/SSH state. The namespace
# gives Bash a real root effective UID while the EUID environment is misleading.
if unshare --user --map-root-user -- true >/dev/null 2>&1; then
  root_command=(unshare --user --map-root-user -- env EUID=1000)
else
  printf 'id() { printf "0\\n"; }\n' >"$root/root-bash-env"
  root_command=(env EUID=1000 BASH_ENV="$root/root-bash-env")
fi
set +e
"${root_command[@]}" HOME="$root/root-home" PATH="$root/bin:$PATH" \
  bash "$(dirname "$0")/../wintix-work-bootstrap.sh" >"$root/root-output" 2>"$root/root-error" </dev/null
root_rc=$?
set -e
(( root_rc != 0 ))
grep -F 'run this command as your normal user' "$root/root-error" >/dev/null
[[ ! -e $root/root-home ]]

run_bootstrap() {
  printf 'Personal User\npersonal@example.invalid\nWork User\nwork@example.invalid\n' |
    HOME="$root/home" XDG_CONFIG_HOME="$root/home/.config" \
    PATH="$root/bin:$PATH" GIT_CONFIG_NOSYSTEM=1 \
    bash "$(dirname "$0")/../wintix-work-bootstrap.sh" > "$root/output" 2> "$root/error"
}

# A fresh run generates two independent local keys and identity files.
run_bootstrap
for kind in personal work; do
  test -f "$root/home/.ssh/id_ed25519_$kind"
  test -f "$root/home/.ssh/id_ed25519_$kind.pub"
done
grep -q 'Personal GitHub public key' "$root/output"
grep -q 'Work Git-provider public key' "$root/output"
grep -q 'name = Personal User' "$root/home/.config/wintix/git-personal.inc"
grep -q 'name = Work User' "$root/home/.config/wintix/git-work.inc"
! test -e "$root/home/.gitconfig"

# Re-running preserves both private and public keys.
find "$root/home/.ssh" -type f -exec sha256sum {} + | sort > "$root/keys-before"
run_bootstrap
find "$root/home/.ssh" -type f -exec sha256sum {} + | sort > "$root/keys-after"
cmp "$root/keys-before" "$root/keys-after"

# A missing public key is safely derived from its private key.
rm "$root/home/.ssh/id_ed25519_personal.pub"
run_bootstrap
grep -q 'derived-id_ed25519_personal' "$root/home/.ssh/id_ed25519_personal.pub"

# An orphan public key fails closed and is not replaced.
rm "$root/home/.ssh/id_ed25519_work"
cp "$root/home/.ssh/id_ed25519_work.pub" "$root/orphan-before"
if run_bootstrap; then
  printf 'bootstrap unexpectedly accepted an orphan public key\n' >&2
  exit 1
fi
cmp "$root/orphan-before" "$root/home/.ssh/id_ed25519_work.pub"
grep -q 'exists without its private key' "$root/error"

# Model Home Manager's declarative conditional includes, then verify effective
# identity and SSH routing in each directory. There is no global fallback.
rm "$root/home/.ssh/id_ed25519_work.pub"
printf 'private-work\n' > "$root/home/.ssh/id_ed25519_work"
printf 'ssh-ed25519 work\n' > "$root/home/.ssh/id_ed25519_work.pub"
run_bootstrap
export HOME="$root/home" GIT_CONFIG_NOSYSTEM=1
personal_inc="$HOME/.config/wintix/git-personal.inc"
work_inc="$HOME/.config/wintix/git-work.inc"
git config --global 'includeIf.gitdir:~/.wintix/.path' "$personal_inc"
git config --global 'includeIf.gitdir:~/Documents/Code/personal/.path' "$personal_inc"
git config --global 'includeIf.gitdir:~/Documents/Code/work/.path' "$work_inc"
for repo in "$HOME/.wintix" "$HOME/Documents/Code/personal/project" "$HOME/Documents/Code/work/project" "$HOME/Documents/other"; do
  mkdir -p "$repo"
  git -C "$repo" init --quiet
 done
! git config --global --get user.name
! git -C "$HOME/Documents/other" config --get user.name
for repo in "$HOME/.wintix" "$HOME/Documents/Code/personal/project"; do
  [[ $(git -C "$repo" config --get user.name) == 'Personal User' ]]
  [[ $(git -C "$repo" config --get user.email) == personal@example.invalid ]]
  [[ $(git -C "$repo" config --get core.sshCommand) == *id_ed25519_personal* ]]
done
[[ $(git -C "$HOME/Documents/Code/work/project" config --get user.name) == 'Work User' ]]
[[ $(git -C "$HOME/Documents/Code/work/project" config --get user.email) == work@example.invalid ]]
[[ $(git -C "$HOME/Documents/Code/work/project" config --get core.sshCommand) == *id_ed25519_work* ]]

printf 'work bootstrap tests passed\n'
