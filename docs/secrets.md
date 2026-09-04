# Git, SSH, and secrets

Git, the GitHub SSH client, and the SSH private key secret are user state managed
by Home Manager. The encrypted key is committed as
`secrets/github-ssh-key.yaml`; Home Manager sops-nix decrypts it to a
user-owned, mode `0400` file below the user's runtime directory. The private key
never enters the Nix store.

The `sops-nix` user service has a runtime condition on
`~/.config/sops/age/keys.txt`. Consequently a missing local age identity skips
decryption cleanly: flake evaluation, `nix flake check`, system builds, install,
and first boot remain pure and do not require any secret or environment switch.

## Normal reinstall

```text
Install Wintix
  -> sign in to Bitwarden
  -> copy the existing AGE-SECRET-KEY
  -> run wintix-secrets-bootstrap and paste it at the hidden prompt
  -> Home Manager sops-nix restores the existing GitHub SSH key
  -> run ssh -T git@github.com
```

`wintix-secrets-bootstrap` validates the identity, installs it atomically with
restrictive permissions, prints its public recipient, and attempts to restart
the `sops-nix` user service. It never replaces an existing identity. A valid
existing identity is an idempotent success; malformed or unexpected existing
material requires deliberate manual recovery. No impure rebuild is involved.

## Initial enrollment

1. Generate a device age identity with
   `age-keygen -o ~/.config/sops/age/keys.txt`, keeping the directory mode
   `0700` and file mode `0600`. Store **only this private age identity** in
   Bitwarden.
2. Derive its public recipient with
   `age-keygen -y ~/.config/sops/age/keys.txt`. Replace
   `AGE_RECIPIENT_REQUIRES_LOCAL_ENROLLMENT` in `.sops.yaml` with that public
   `age1...` value and review the change.
3. Run `wintix-secrets-enroll`. It generates the dedicated key
   `~/.ssh/wintix_github_ed25519`, shows only its public key, encrypts the private
   key through a mode-`0600` temporary file, validates the SOPS result, and
   atomically replaces the repository enrollment marker.
4. Register the displayed `.pub` key in GitHub. The command intentionally does
   not modify the GitHub account.
5. Commit only `.sops.yaml` and `secrets/github-ssh-key.yaml`, restart the
   `sops-nix` user service, and run `ssh -T git@github.com`.

The helper refuses existing SSH or encrypted material by default. To
deliberately re-encrypt the same validated key, use
`wintix-secrets-enroll --use-existing-key --replace-encrypted`. These flags make
credential reuse and encrypted-payload replacement explicit; they never
overwrite the SSH key itself.

## Rotation

Create a replacement at a protected Wintix-specific path (moving the old pair to
a protected backup first if necessary), update `.sops.yaml` if the age identity
also changes, and run enrollment with `--replace-encrypted`. Register and verify
the replacement with `ssh -T git@github.com`; only then revoke the old GitHub key
and remove protected backups. Rotation is never automatic.

Bitwarden contains only the age private identity. Git contains only the public
age recipient and SOPS-encrypted material. The dedicated GitHub SSH key persists
across reinstalls of this device; different devices should have different SSH
keys. No private credential may ever be committed.
