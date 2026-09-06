{ pkgs, ... }:

{
  environment.systemPackages = [ pkgs.git ];

  # The Docker package provides the Compose and Buildx CLI plugins. Users are
  # deliberately not members of the docker group and invoke Docker via sudo.
  virtualisation.docker.enable = true;
}
