{
  description = "Hunt every Endpoint in your code, expose Shadow APIs, map the Attack Surface";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        noir = pkgs.crystal.buildCrystalPackage rec {
          pname = "noir";
          version = "0.26.0";

          src = ./.;

          shardsFile = ./shards.nix;

          crystalBinaries.noir.src = "src/noir.cr";

          crystalBinaries.noir.options = [ "--release" "--no-debug" ];

          nativeBuildInputs = [ pkgs.crystal pkgs.shards ];
          buildInputs = [ ];  # 필요 시 추가 (e.g., pkgs.openssl)

          buildPhase = ''
              runHook preBuild
              shards build --release
              runHook postBuild
            '';

          installPhase = ''
              runHook preInstall
              mkdir -p $out/bin
              cp bin/noir $out/bin/noir
              runHook postInstall
            '';

          doCheck = false;

          meta = with pkgs.lib; {
            description = "OWASP Noir: Hunt every Endpoint in your code, expose Shadow APIs, map the Attack Surface";
            homepage = "https://github.com/owasp-noir/noir";
            license = licenses.mit;
            maintainers = [ "hahwul" "ksg97031" ];
            mainProgram = "noir";
          };
        };
      in
      {
        packages.default = noir;

        devShells.default = pkgs.mkShell {
          inputsFrom = [ noir ];
          nativeBuildInputs = with pkgs; [ crystal shards crystal2nix ];
          shellHook = ''
            echo "OWASP Noir development environment loaded (via Nix)"
            echo "Running shards install..."
            shards install || true
          '';
        };
      });
}
