{
  config,
  lib,
  pkgs,
  ...
}:

let
  braveReconcile = pkgs.writeShellApplication {
    name = "wintix-brave-reconcile";
    runtimeInputs = with pkgs; [
      coreutils
      jq
    ];
    text = builtins.readFile ./brave-reconcile.sh;
  };
in
{
  programs.brave = {
    enable = true;
    extensions = [
      { id = "mlomiejdfkolichcflejclcbmpeaniij"; } # Ghostery AdBlocker for Privacy
      { id = "mnjggcdmjocbbbhaepdhchncahnbgone"; } # SponsorBlock for YouTube
      { id = "cimiefiiaegbelhefglklhhakcgmhkai"; } # KDE Plasma Integration
      { id = "nngceckbapebfimnlniiiahkandclblb"; } # Bitwarden Password Manager
    ];
  };

  home.activation.braveReconcile = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${braveReconcile}/bin/wintix-brave-reconcile
  '';
}
