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
  end
end
