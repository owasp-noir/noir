# Example overlay for adding noir to nixpkgs
# This file demonstrates how noir can be added to nixpkgs
# Usage: import this overlay in your nixpkgs configuration

final: prev: {
  noir = prev.callPackage ../default.nix { };
}