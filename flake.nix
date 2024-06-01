{
  description = "gitops-bootstrap";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux"];

      perSystem = {
        pkgs,
        lib,
        ...
      }: {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            helm
          ];
          name = "helm";

          shellHook = ''
            echo -e "\n\033[1;36m❄️ Welcome to the '${name}' devshell ❄️\033[0m\n"
            echo
          '';
        };
      };
    };
}
