{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
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
}