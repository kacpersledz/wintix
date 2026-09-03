# Git, SSH, and secrets

Git and the SSH client are configured by Home Manager. The GitHub private key
is device-specific, encrypted in the repository with SOPS, and materialized by
sops-nix at `/run/secrets/wintix-github-ssh`; plaintext never enters the Nix
store. The age identity that unlocks it lives only at
`~/.config/sops/age/keys.txt` and in Bitwarden.

## Normal reinstall

The installer deliberately evaluates with secrets disabled, so installation
and first boot do not need an age identity. After boot:

1. Sign in to Bitwarden manually and copy this device's Wintix age identity.
2. Run `wintix-secrets-bootstrap`, paste it at the hidden prompt, and press Enter.
3. Run `wintix-rebuild`. The wrapper notices the identity and enables the
   secret-dependent configuration for this rebuild.
4. Verify `ssh -T git@github.com` and `git config --get-regexp '^user\.'`.

The bootstrap command never replaces an existing file. If deliberate recovery
or rotation is necessary, first move the old file to a protected backup, then
run the command again. Never paste the identity into a command argument.

## One-time enrollment (manual, local only)

Enrollment is intentionally not automated. Perform it on the target device:

1. Run `mkdir -m 700 -p ~/.config/sops/age`, set `umask 077`, and run
   `age-keygen -o ~/.config/sops/age/keys.txt`.
2. Store **only** the `AGE-SECRET-KEY-...` private identity in Bitwarden. Never
   commit it.
3. Run `age-keygen -y ~/.config/sops/age/keys.txt` and replace the enrollment
   marker in `.sops.yaml` with the resulting public `age1...` recipient.
4. Generate or select a dedicated desktop Ed25519 GitHub key at a clearly named
   local path, for example `~/.ssh/wintix_github_ed25519`. Do not overwrite
   `~/.ssh/id_ed25519` or another existing key.
5. Register that key's `.pub` contents in GitHub's SSH key settings.
6. From the repository root, encrypt the private key without copying it into a
   tracked plaintext file:

   ```sh
   mkdir -p secrets
   sops --set '["github_ssh_private_key"] load("/home/january/.ssh/wintix_github_ed25519")' \
     secrets/github-ssh-key.yaml
   ```

7. Inspect `sops -d secrets/github-ssh-key.yaml` locally, taking care not to
   redirect, log, or commit its output. Confirm the encrypted file contains a
   `sops` metadata section and no plaintext private-key header.
8. Commit only `.sops.yaml` and the SOPS-encrypted YAML, then run
   `wintix-rebuild`.
9. Run `ssh -T git@github.com` and confirm authentication uses the intended
   account.
10. Run `git config --get user.name` and `git config --get user.email` and
    confirm the declarative public identity.

This repository intentionally does not yet include a production recipient or
encrypted payload: the device owner must perform enrollment before those two
safe-to-publish artifacts can be committed.

## Rotation

Generate the replacement credential, update recipients and encrypted material,
verify decryption and GitHub access with the new setup, and only then revoke or
remove the old credential. Keep every private age identity and plaintext SSH
private key outside Git and remove protected backups only after verification.
