{
  description = "Hunt every Endpoint in your code, expose Shadow APIs, map the Attack Surface";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (final: prev: {
              # Crystal(1.19.x)가 LLVM 22.1을 끌고 오고 있음. 다만 현재 LLVM 22.1은 빌드가 깨짐.
              # 그래서 devShell 진입이 불가하고 우선 이를 대응하기 위해 LLVM 21로 고정합니다. (깨짐은 macOS 기준)
              crystal =
                let
                  llvmPackages =
                    prev.llvmPackages_21
                      or (throw "llvmPackages_21 not found in this nixpkgs; update/pin nixpkgs to a revision that provides LLVM 21");
                in
                # `pkgs.crystal`이 makeOverridable이 아니라 `override`가 없어서(callPackage로) 재정의
                (prev.callPackage (prev.path + "/pkgs/development/compilers/crystal") {
                  # crystal 1.19.1은 기본적으로 llvmPackages_22(LLVM 22.1)를 사용
                  # 여기서는 llvmPackages_22를 llvmPackages_21로 치환해 LLVM 21을 강제로 사용하게 합니다.
                  llvmPackages_22 = llvmPackages;
                }).crystal;
            })
          ];
        };

        noir = pkgs.crystal.buildCrystalPackage rec {
          pname = "noir";
          version = "0.27.0";

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
