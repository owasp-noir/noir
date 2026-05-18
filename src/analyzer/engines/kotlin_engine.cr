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
    def self.test_path?(path : String) : Bool
      return true if path.includes?("/src/test/")
      return true if path.includes?("/jvmTest/")
      return true if path.includes?("/commonTest/")
      return true if path.includes?("/jsTest/")
      return true if path.includes?("/nativeTest/")
      return true if path.includes?("/test/")
      return true if path.includes?("/testData/")
      base = File.basename(path)
      return true if base.ends_with?("Test.kt")
      base.ends_with?("Tests.kt")
    end
  end
end
