{
  description = "OWASP Noir - Attack surface detector that identifies endpoints by static analysis";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        noir = pkgs.callPackage ./default.nix { };
      in
      {
        packages = {
          default = noir;
          noir = noir;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            crystal
            shards
            just
            # Development tools
            ameba
          ];

          shellHook = ''
            echo "OWASP Noir development environment"
            echo "Available commands:"
            echo "  just --list    # List available build tasks"
            echo "  just build     # Build the application"
            echo "  just test      # Run tests"
            echo "  just check     # Check code format and run linter"
            echo ""
            echo "Crystal version: $(crystal --version | head -1)"
          '';
        };

        # Convenience alias for nix run
        apps.default = flake-utils.lib.mkApp {
          drv = noir;
        };
      });
}