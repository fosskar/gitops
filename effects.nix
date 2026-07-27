{ inputs, ... }:
let
  pkgs = inputs.nixpkgs.legacyPackages.x86_64-linux;
  inherit (inputs.nixbot.lib.effects { inherit pkgs; }) mkEffect;
in
{
  flake.herculesCI = _args: {
    # Renovate clones the repo itself, so this needs no checkout. It only
    # sees fosskar/gitops: nixbot's GitToken is a github app installation
    # token scoped to the repo the schedule belongs to, so a central
    # renovate run in another repo could not reach this one.
    onSchedule.renovate = {
      when = {
        hour = 19;
        minute = 0;
      };
      outputs.effects.renovate = mkEffect {
        name = "effect-renovate";
        inputs = [
          pkgs.renovate
          pkgs.git
          pkgs.fluxcd
        ];
        secretsMap.git.type = "GitToken";
        effectScript = ''
          set -euo pipefail

          # node's child_process.exec spawns /bin/sh by absolute path; the
          # bubblewrap sandbox has no /bin, so renovate's flux artifact step
          # fails with "spawn /bin/sh ENOENT" even with flux in PATH. the
          # sandbox root is writable: shim it.
          mkdir -p /bin
          ln -sf "$(command -v sh)" /bin/sh
          token=$(jq -re '.git.data.token' "$HERCULES_CI_SECRETS_JSON")
          export RENOVATE_TOKEN="$token"
          export RENOVATE_GITHUB_COM_TOKEN="$token"

          export RENOVATE_PLATFORM=github
          export RENOVATE_REPOSITORIES=fosskar/gitops
          export RENOVATE_GIT_AUTHOR='fosskar[bot] <300917551+fosskar[bot]@users.noreply.github.com>'
          export RENOVATE_BINARY_SOURCE=global
          export LOG_LEVEL=info

          renovate
        '';
      };
    };

    onSchedule.update-flake-inputs = {
      when = {
        hour = 3;
        minute = 0;
      };
      # nixbot mounts a pushable clone of the effect's commit at
      # $NIXBOT_EFFECT_CHECKOUT, which is also the working directory. The
      # updater lives in the nixfiles flake; no flake input required.
      outputs.effects.update-flake-inputs = mkEffect {
        name = "effect-update-flake-inputs";
        checkout = true;
        # nixVersions.latest, not pkgs.nix: nixfiles' flake.nix overrides
        # inputs of transitive inputs (llm-agents/bun2nix, tangled/gomod2nix/
        # flake-utils), which nix < 2.30 cannot apply. It then re-resolves
        # those as indirect flakerefs and fails on the empty registry.
        inputs = [
          pkgs.git
          pkgs.nixVersions.latest
        ];
        secretsMap.git.type = "GitToken";
        effectScript = ''
          set -euo pipefail
          token=$(jq -re '.git.data.token' "$HERCULES_CI_SECRETS_JSON")
          export FORGE_TOKEN="$token"
          export GITHUB_TOKEN="$token"
          export NIX_CONFIG="experimental-features = nix-command flakes
          access-tokens = github.com=$token"

          git config --global user.name 'fosskar[bot]'
          git config --global user.email '300917551+fosskar[bot]@users.noreply.github.com'

          nix run "github:fosskar/nixfiles#updater-flake-inputs"
        '';
      };
    };
  };
}
