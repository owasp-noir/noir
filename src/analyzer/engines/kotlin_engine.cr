require "../../models/analyzer"

# Shared helpers for the three Kotlin analyzers (ktor / spring /
# http4k). They each extend `Analyzer` directly rather than a
# language-specific engine, so the helpers live as class methods on
# `Analyzer::Kotlin::KotlinEngine` and the callers import it
# explicitly. Promoting to a real engine class would be churn for
# little gain — three analyzers, one helper.
module Analyzer::Kotlin
  module KotlinEngine
    # Standard Kotlin/JUnit/Gradle test-source conventions:
    #
    #   * `/src/test/`                — Maven/Gradle JVM test root
    #   * `/jvmTest/` `/commonTest/`  — Gradle Kotlin Multiplatform test source sets
    #   * `/jsTest/` `/nativeTest/`
    #   * `/test/` anywhere under a Gradle `kotlin { }` source dir (KMP
    #     uses `<target>/test/` rather than the `src/test/` Maven layout)
    #   * `/testData/`                — Kotlin compiler-plugin fixture dir
    #     used by `ktor-compiler-plugin/testData/...`
    #   * Filenames ending in `Test.kt` / `Tests.kt` — JUnit/Kotest
    #
    # ktor's own repo registers ~370 phantom endpoints from
    # `ktor-client/...-tests/` modules and `*/jvm/test/...` directories
    # that exercise the routing DSL under inline test servers.
    #
    # Takes the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one. `/test/` is generic enough that matching the
    # absolute path made the answer depend on where the checkout lived:
    # the same tree under `~/work/test/` reported 0 endpoints instead of
    # 93.
    #
    # One precompiled `Regex.union` (PCRE2 JIT, auto-escapes each literal)
    # replaces the seven OR-ed `String#includes?` passes — equivalent to
    # any of those substrings. Basename `Test.kt` / `Tests.kt` checks stay
    # separate: putting them in the union would also match mid-path
    # segments like `.../FooTest.kt/bar.kt`.
    TEST_PATH_RE = Regex.union(
      "/src/test/",
      "/jvmTest/",
      "/commonTest/",
      "/jsTest/",
      "/nativeTest/",
      "/test/",
      "/testData/",
    )

    def self.test_path?(relative_path : String) : Bool
      return true if relative_path.matches?(TEST_PATH_RE)
      base = File.basename(relative_path)
      return true if base.ends_with?("Test.kt")
      base.ends_with?("Tests.kt")
    end
  end
end
