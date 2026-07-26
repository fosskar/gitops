{
  description = "gitops";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    nixbot = {
      url = "github:Mic92/nixbot";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      imports = [ ./effects.nix ];

      perSystem =
        {
          pkgs,
          ...
        }:
        {
          devShells.default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [
              kubernetes-helm
              argocd
              kubeseal
            ];
            name = "gitops";
          };
        };
    };
}
