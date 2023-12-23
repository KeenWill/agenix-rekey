{
  inputs = {
    devshell = {
      url = "github:numtide/devshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    systems.url = "github:nix-systems/default";
    flake-utils.url = "github:numtide/flake-utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    pre-commit-hooks = {
      url = "github:cachix/pre-commit-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  description = "An agenix extension adding secret generation and automatic rekeying using a YubiKey or master-identity";
  outputs = {
    self,
    nixpkgs,
    flake-utils,
    devshell,
    pre-commit-hooks,
    ...
  }: let
    allApps = ["edit" "generate" "rekey"];
  in
    {
      nixosModules.agenixRekey = import ./modules/agenix-rekey.nix nixpkgs;
      nixosModules.default = self.darwinModules.agenixRekey;
      darwinModules.agenixRekey = import ./modules/agenix-rekey.nix nixpkgs;
      darwinModules.default = self.darwinModules.agenixRekey;

      # A nixpkgs overlay that adds the agenix CLI wrapper
      overlays.default = self.overlays.agenix-rekey;
      overlays.agenix-rekey = _final: prev: {
        agenix-rekey = prev.callPackage ./nix/package.nix {
          inherit allApps;
        };
      };

      configure = {
        # The path of the user's flake. Needed to run a sandbox-relaxed
        # app that saves the rekeyed outputs.
        userFlake,
        # All nixos definitions that should be considered for rekeying
        nodes,
        # The package sets to use. pkgs.${system} must yield an initialized nixpkgs package set
        pkgs ? self.pkgs,
      }:
        flake-utils.lib.eachDefaultSystem (system: {
          apps = pkgs.${system}.lib.genAttrs allApps (app:
            import ./apps/${app}.nix {
              inherit nodes userFlake;
              pkgs = pkgs.${system};
            });
        });

      # XXX: deprecated, scheduled for removal in 2024. Use the package instead of
      # defining apps. This is just a compatibility wrapper that defines apps with
      # the same interface as before.
      defineApps = argsOrSelf: pkgs: nodes:
        pkgs.lib.warn ''
          The `agenix-rekey.defineApps self pkgs nodes` function is deprecated and will
          be removed in 2024. The new approach will unclutter your flake's app definitions
          and provide a hermetic entrypoint for agenix-rekey, which can be accessed more
          egonomically via a new CLI wrapper 'agenix'. Alternatively via you can still run
          the scripts directly from your flake using `nix run .#agenix-rekey.apps.$system.<app>`,
          in case you don't want to use the wrapper.

          Please remove your current `agenix-rekey.defineApps` call entirely from your apps
          and instead add a new top-level output like this:

            agenix-rekey = agenix-rekey.configure {
              userFlake = self;
              nodes = self.nixosSystems;
            };

          The new wrapper CLI can be accessed via `nix shell github:oddlama/agenix-rekey` or by
          adding `agenix-rekey.packages.''${system}.default` to your devshell. For more information,
          please visit the github page and refer to the updated instructions in the README.''
        (import ./apps) {
          userFlake = argsOrSelf; # argsOrSelf = self
          inherit pkgs nodes;
        };
    }
    // flake-utils.lib.eachDefaultSystem (system: rec {
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          devshell.overlays.default
          self.overlays.default
        ];
      };

      # `nix build`
      packages.default = packages.agenix-rekey;
      # `nix build .#agenix-rekey`
      packages.agenix-rekey = pkgs.agenix-rekey;

      # `nix run`
      apps.default = flake-utils.lib.mkApp {drv = packages.agenix-rekey;};

      # `nix flake check`
      checks.pre-commit-hooks = pre-commit-hooks.lib.${system}.run {
        src = nixpkgs.lib.cleanSource ./.;
        hooks = {
          alejandra.enable = true;
          deadnix.enable = true;
          statix.enable = true;
        };
      };

      # `nix develop`
      devShells.default = pkgs.devshell.mkShell {
        name = "agenix-rekey";
        commands = with pkgs; [
          {
            package = alejandra;
            help = "Format nix code";
          }
          {
            package = statix;
            help = "Lint nix code";
          }
          {
            package = deadnix;
            help = "Find unused expressions in nix code";
          }
        ];

        devshell.startup.pre-commit.text = self.checks.${system}.pre-commit-hooks.shellHook;
      };
    });
}
