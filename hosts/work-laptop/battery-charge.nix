{ pkgs, ... }:

let
  batteryChargeHelper = pkgs.writeShellApplication {
    name = "wintix-battery-charge";
    runtimeInputs = with pkgs; [ coreutils ];
    text = builtins.readFile ./battery-charge-helper.sh;
  };
  mkChargeCommand = name: pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = with pkgs; [ coreutils sudo ];
    text = builtins.replaceStrings
      [ "@batteryChargeHelper@" ]
      [ "${batteryChargeHelper}/bin/wintix-battery-charge" ]
      (builtins.readFile ./battery-charge-command.sh);
  };
  chargeCare = mkChargeCommand "wintix-charge-care";
  chargeFull = mkChargeCommand "wintix-charge-full";
in
{
  users.users.ksledz.packages = [ chargeCare chargeFull ];

  systemd.services.wintix-battery-charge-care = {
    description = "Set work-laptop battery care thresholds";
    wantedBy = [ "multi-user.target" ];
    restartIfChanged = false;
    stopIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${batteryChargeHelper}/bin/wintix-battery-charge care";
    };
  };
}
