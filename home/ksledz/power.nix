{ ... }:
{
  programs.plasma.powerdevil = {
    AC.powerProfile = "performance";
    battery.powerProfile = "balanced";
    lowBattery.powerProfile = "powerSaving";
    batteryLevels.lowLevel = 40;
  };
}
