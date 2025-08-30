{ lib
, crystal
, fetchFromGitHub
, just
, shards
, stdenv
}:

crystal.buildCrystalPackage rec {
  pname = "noir";
  version = "0.23.1";

  src = ./.;

  nativeBuildInputs = [ just shards ];

  # Crystal dependencies are handled by shards
  shardsFile = ./shard.lock;

  # Build command using just instead of crystal directly
  buildPhase = ''
    runHook preBuild
    just build
    runHook postBuild
  '';

  # Install the binary
  installPhase = ''
    runHook preInstall
    install -Dm755 bin/noir $out/bin/noir
    runHook postInstall
  '';

  # Run tests
  doCheck = true;
  checkPhase = ''
    runHook preCheck
    just test
    runHook postCheck
  '';

  meta = with lib; {
    description = "Attack surface detector that identifies endpoints by static analysis";
    homepage = "https://github.com/owasp-noir/noir";
    changelog = "https://github.com/owasp-noir/noir/releases/tag/v${version}";
    license = licenses.mit;
    maintainers = with maintainers; [ ];
    platforms = platforms.unix;
    mainProgram = "noir";
  };
}