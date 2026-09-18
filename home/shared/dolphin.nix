{ pkgs, ... }:

let
  extractToFolder = pkgs.writeShellApplication {
    name = "wintix-dolphin-extract-to-folder";
    runtimeInputs = with pkgs; [
      coreutils
      kdePackages.ark
      libnotify
    ];
    text = builtins.readFile ./dolphin-extract-to-folder.sh;
  };
in
{
  xdg.dataFile."kio/servicemenus/wintix-extract-to-folder.desktop" = {
    executable = true;
    text = ''
      [Desktop Entry]
      Type=Service
      Name=Extract to archive folder
      MimeType=application/zip;
      Actions=extractToArchiveFolder;
      X-KDE-Protocol=file
      X-KDE-RequiredNumberOfUrls=1
      X-KDE-Priority=TopLevel

      [Desktop Action extractToArchiveFolder]
      Name=Extract to archive folder
      Icon=archive-extract
      Exec=${extractToFolder}/bin/wintix-dolphin-extract-to-folder %f
    '';
  };
}
