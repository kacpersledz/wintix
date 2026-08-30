# Wintix

Wintix is a personal declarative NixOS configuration. It currently contains the `desktop` host.

To apply the configuration:

```sh
sudo nixos-rebuild switch --flake .#desktop
```
