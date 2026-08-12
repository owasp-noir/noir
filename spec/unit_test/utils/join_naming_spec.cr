require "../../spec_helper"
require "../../../src/utils/url_path"

# `join_path` / `join_paths` was 21 definitions with 12 distinct behaviours,
# two of them at top level: `Object#join_paths` (a `File.join` alias, in
# `src/analyzer/analyzer.cr`) and a variadic `join_path` in
# `src/utils/utils.cr`. Crystal resolves by type, not by lexical namespace,
# so unqualified calls in `java/spring.cr` and `kotlin/spring.cr` fell
# through to the `File.join` one and composed URLs with filesystem-path
# semantics — `"/portal" + ""` became `"/portal/"`. See #2489.
#
# Both names are now banned. Shared semantics live on `Noir::URLPath` under
# names that state the rule (`join`, `join_trimmed`, `join_absorbing`,
# `join_rooted`, `absolute_join`); a framework-specific joiner is named
# after the construct it composes (`nest_join`, `group_join`, `mount_join`,
# `namespace_join`, `route_scope_join`, …). See #2493.
#
# The compiler covers the *call* side for free: with no top-level
# definition, a bare `join_paths(a, b)` is a compile error. It cannot cover
# the *definition* side — nothing stops a new `private def join_paths`
# inside a class, which is exactly how the collision grew to 21. That is
# what this spec is for.
#
# A top-level poison definition would be worse than useless here: Crystal
# resolves by overload specificity, so re-adding `def join_paths(prefix :
# String, path : String)` would simply win over a poison `def
# join_paths(*args)` and the trap would never fire.
BANNED_JOIN_DEF = /^\s*(?:private\s+|protected\s+)?def\s+(?:self\.)?join_paths?\b/

describe "path-joining method names" do
  sources = Dir.glob("src/**/*.cr").sort

  it "defines no method named join_path or join_paths under src/" do
    offenders = sources.flat_map do |file|
      File.read_lines(file).each_with_index.compact_map do |line, index|
        "#{file}:#{index + 1}: #{line.strip}" if line.matches?(BANNED_JOIN_DEF)
      end
    end

    fail <<-MSG unless offenders.empty?
      `join_path` / `join_paths` are banned names — they collided across 21
      definitions with 12 behaviours. Put shared semantics on
      `Noir::URLPath`, or name the method after the framework construct it
      composes. Offending definitions:
        #{offenders.join("\n  ")}
      MSG
  end

  # Guards the guard: a typo in the glob would make the example above pass
  # vacuously, which is the failure mode that makes source-scanning specs
  # worthless.
  it "scans the whole source tree" do
    sources.size.should be > 500
    sources.count { |f| File.read(f).includes?("Noir::URLPath") }.should be > 20
  end
end
