require "../../models/analyzer"

# Shared helpers for the Java analyzers. They each extend `Analyzer`
# directly rather than a language-specific engine (historically the
# Java set was the first family to land and never got an intermediate
# class), so the helpers live as class methods on the JavaEngine
# module and the callers import it explicitly. Mirrors the pattern
# `Analyzer::Kotlin::KotlinEngine` follows.
module Analyzer::Java
  module JavaEngine
    # Maven/Gradle pin test sources to `src/test/<lang>/` — `java`,
    # `kotlin`, `scala`, `groovy` all share the layout. Real route
    # handlers never live there, but Quarkus, Micronaut, Spring,
    # Javalin, JAX-RS and friends routinely declare inline
    # controllers under `src/test/java/...` to exercise the
    # framework. The path layout is part of the build tool's
    # contract so the prefix check is unambiguous.
    #
    # Also covers Maven's archetype source-roots
    # (`src/it/`, integration-test convention used by some Quarkus
    # extensions and Apache projects) which sit alongside `src/test/`.
    #
    # Takes the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one. The layout is a contract between the build
    # tool and the *project*, so matching the absolute path let a
    # directory above the scan base decide the answer — a CI job that
    # checks out under a `src/test/` step directory silently lost 375 of
    # the fixture tree's 396 endpoints.
    def self.test_path?(relative_path : String) : Bool
      return true if relative_path.includes?("/src/test/")
      return true if relative_path.includes?("/src/it/")
      false
    end

    # Index of the delimiter closing the `open_char` at `open_idx`, or nil when
    # the source runs out first. String and char literals are skipped, so a
    # `)`/`}` inside `"…"` or `'…'` cannot close the block early.
    #
    # Scan by CHARACTER (not byte): `open_idx` is a char index from
    # `String#index` and callers char-slice with — or range-compare — the
    # returned index. A byte scan corrupts both on multi-byte UTF-8.
    # ASCII-identical to the previous byte loop.
    def self.find_matching_delimiter(code : String,
                                     open_idx : Int32,
                                     open_char : Char,
                                     close_char : Char) : Int32?
      depth = 1
      in_string = false
      quote = '\0'
      escape = false

      code.each_char_with_index do |ch, i|
        next if i <= open_idx
        if in_string
          if escape
            escape = false
          elsif ch == '\\'
            escape = true
          elsif ch == quote
            in_string = false
          end
        else
          if ch == '"' || ch == '\''
            in_string = true
            quote = ch
          elsif ch == open_char
            depth += 1
          elsif ch == close_char
            depth -= 1
          end
        end
        return i if depth == 0
      end

      nil
    end
  end
end
