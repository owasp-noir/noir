# Compile-time helper for `src/tagger/rule_tagger.cr` (lives under `src/` so
# packagers that copy only `src/`, like the Nix flake, still have it): prints every rule
# file in the given directory as a Crystal `{filename, content}` literal, so
# the rules ship inside the binary and adding one needs no list edit.
dir = ARGV[0]
files = Dir.glob(File.join(dir, "*.{yml,yaml}")).sort!
entries = files.map { |path| "{#{File.basename(path).inspect}, #{File.read(path).inspect}}" }
puts "[#{entries.join(", ")}] of Tuple(String, String)"
