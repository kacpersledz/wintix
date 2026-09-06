#!/usr/bin/env bash
set -euo pipefail
root=$(mktemp -d); trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin" "$root/home/.ssh"
printf 'existing-private\n' > "$root/home/.ssh/id_ed25519"
printf 'ssh-ed25519 existing-public test\n' > "$root/home/.ssh/id_ed25519.pub"
cp "$root/home/.ssh/id_ed25519" "$root/before"
printf '%s\n' '#!/usr/bin/env bash' 'exit 99' > "$root/bin/ssh-keygen"; chmod +x "$root/bin/ssh-keygen"
printf 'Work User\nwork@example.invalid\n' | HOME="$root/home" PATH="$root/bin:$PATH" bash "$(dirname "$0")/../wintix-work-bootstrap.sh" > "$root/output"
cmp "$root/before" "$root/home/.ssh/id_ed25519"
grep -q 'name = Work User' "$root/home/.config/wintix/work-git.inc"
grep -q 'email = work@example.invalid' "$root/home/.config/wintix/work-git.inc"
grep -q 'ssh-ed25519 existing-public' "$root/output"
printf 'work bootstrap tests passed\n'
