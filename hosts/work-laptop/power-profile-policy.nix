{ lib, pkgs, ... }:

let
  powerProfilePolicy = pkgs.writeShellApplication {
    name = "wintix-power-profile-policy";
    runtimeInputs = with pkgs; [
      coreutils
      power-profiles-daemon
      systemd
    ];
    text = ''
      shopt -s nullglob

      on_ac_power() {
        local supply type online
        for supply in /sys/class/power_supply/*; do
          [[ -r "$supply/type" && -r "$supply/online" ]] || continue
          type="$(<"$supply/type")"
          online="$(<"$supply/online")"
          if [[ "$type" != "Battery" && "$online" == "1" ]]; then
            return 0
          fi
        done
        return 1
      }

      battery_capacity() {
        local battery capacity_file
        for battery in /sys/class/power_supply/BAT*; do
          capacity_file="$battery/capacity"
          [[ -r "$capacity_file" ]] || continue
          cat "$capacity_file"
          return 0
        done
        echo "No readable battery capacity found" >&2
        return 1
      }

      apply_profile() {
        local desired current capacity
        if on_ac_power; then
          desired="performance"
        else
          capacity="$(battery_capacity)"
          if (( capacity <= 50 )); then
            desired="power-saver"
          else
            desired="balanced"
          fi
        fi

        current="$(powerprofilesctl get)"
        if [[ "$current" != "$desired" ]]; then
          powerprofilesctl set "$desired"
        fi
      }

      apply_profile

      udevadm monitor --kernel --subsystem-match=power_supply |
        while IFS= read -r _; do
          apply_profile
        done
    '';
  };
in
{
  services.power-profiles-daemon.enable = true;

  systemd.services.wintix-power-profile-policy = {
    description = "Apply the Wintix work-laptop power profile policy";
    wantedBy = [ "multi-user.target" ];
    wants = [ "power-profiles-daemon.service" ];
    after = [ "power-profiles-daemon.service" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = lib.getExe powerProfilePolicy;
      Restart = "always";
      RestartSec = 2;
    };
  };
}
