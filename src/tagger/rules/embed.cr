# Compile-time helper for `src/tagger/rule_tagger.cr` (lives under `src/` so
# packagers that copy only `src/`, like the Nix flake, still have it): prints every rule
# file in the given directory as a Crystal `{filename, content}` literal, so
# the rules ship inside the binary and adding one needs no list edit.
dir = ARGV[0]
# `Dir.children`, not `Dir.glob`: on Windows `__DIR__` has backslashes,
# which a glob pattern reads as escapes, and the build shipped no rules.
names = Dir.children(dir).select { |name| name.ends_with?(".yml") || name.ends_with?(".yaml") }.sort!
entries = names.map { |name| "{#{name.inspect}, #{File.read(File.join(dir, name)).inspect}}" }
puts "[#{entries.join(", ")}] of Tuple(String, String)"
