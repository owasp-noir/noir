require "json"
require "./catalog/*"

module NoirTechs
  TECHS = Catalog::ASP
    .merge(Catalog::ASPNET)
    .merge(Catalog::CFML)
    .merge(Catalog::CLOJURE)
    .merge(Catalog::CPP)
    .merge(Catalog::CRYSTAL)
    .merge(Catalog::CSHARP)
    .merge(Catalog::DART)
    .merge(Catalog::ELIXIR)
    .merge(Catalog::ERLANG)
    .merge(Catalog::FSHARP)
    .merge(Catalog::GLEAM)
    .merge(Catalog::GO)
    .merge(Catalog::GROOVY)
    .merge(Catalog::HASKELL)
    .merge(Catalog::JAVA)
    .merge(Catalog::JAVASCRIPT)
    .merge(Catalog::KOTLIN)
    .merge(Catalog::LUA)
    .merge(Catalog::MOBILE)
    .merge(Catalog::PERL)
    .merge(Catalog::PHP)
    .merge(Catalog::PYTHON)
    .merge(Catalog::R)
    .merge(Catalog::RUBY)
    .merge(Catalog::RUST)
    .merge(Catalog::SCALA)
    .merge(Catalog::SPECIFICATION)
    .merge(Catalog::SWIFT)
    .merge(Catalog::TYPESCRIPT)
    .merge(Catalog::ZIG)

  # Derived from the per-tech :context flags in the catalog files, so a
  # capability can only be declared on an entry that exists — the drift
  # class the tech-registry integrity spec (#2384) exists to catch.
  CALLEE_SUPPORTED_TECHS = TECHS.compact_map do |key, value|
    context = value[:context]?
    next unless context.is_a?(Hash)
    key.to_s if context[:callee]?
  end

  AI_CONTEXT_GUARD_SUPPORTED_TECHS = TECHS.compact_map do |key, value|
    context = value[:context]?
    next unless context.is_a?(Hash)
    key.to_s if context[:guards]?
  end

  # "When both are detected, X owns the routes and Y is noise" — declared on
  # X's catalog entry as `:supersedes => ["y"]`.
  #
  # These rules used to be an `if` chain in `filter_redundant_generic_techs`,
  # a global function in `src/analyzer/analyzer.cr`, so adding a framework
  # that shadows another meant editing the catalog, the analyzer, *and* that
  # function — and none of the four rules had a unit test.
  #
  # ## When a rule belongs here
  #
  # Only when both techs target the *same routing DSL*, so the two analyzers
  # would extract the same endpoints twice under two different technology
  # tags. Lumen/Laravel, Bandit/Plug, Jetzig/httpz, Drupal/Symfony are all
  # that shape: one framework is literally built on the other, so the
  # broader detector fires on every project of the narrower one.
  #
  # ## When a rule does NOT belong here
  #
  # **Never add "the generic stdlib analyzer is redundant when framework X
  # is present".** `techs` is a flat, repo-wide list with no path
  # granularity, so a framework detected *anywhere* would suppress the
  # generic analyzer *everywhere*. In a monorepo that silently drops real
  # attack surface: a standalone `net/http` admin listener exposing
  # /debug/pprof next to a Gin API, or a standalone Starlette service next
  # to a FastAPI one. Framework-vs-framework rules are safe because both
  # analyzers target the same DSL; framework-vs-stdlib rules are not.
  # Scoping that correctly needs a per-tech path map from the detector
  # (the detect loop does know the file), not a global list.
  #
  # `php_pure` and `cfml_pure` are the worked example of getting this wrong.
  # Both used to be dropped when a framework was present, and both paid for
  # it: a legacy `public/upload.php` beside a Laravel app vanished from the
  # report, and so did the `access="remote"` methods on a ColdBox app's
  # proxy components. `php_pure` now resolves URLs against the document
  # root (#2358) and `cfml_pure` narrows to components-only mode, so both
  # run alongside the framework analyzer instead of being suppressed.
  # Neither carries `:supersedes`, deliberately.
  #
  # `:similar` already puts `Array(String)` in the value union, so this key
  # widens nothing — but narrow with `is_a?(Array)`, not `is_a?(Hash)`.
  SUPERSEDES = TECHS.compact_map do |key, value|
    targets = value[:supersedes]?
    next unless targets.is_a?(Array)
    {key.to_s, targets.map(&.to_s)}
  end.to_h

  # Techs that `tech` displaces when both are detected. Empty for the 235
  # entries that displace nothing.
  def self.supersedes(tech : String) : Array(String)
    SUPERSEDES[tech]? || [] of String
  end

  def self.techs
    TECHS
  end

  # Aliases claimed by more than one tech — genuine cross-language
  # library-name ambiguity (`argparse` is C++, Lua *and* Python; `spring` is
  # Java and Kotlin). Without a pin, `similar_to_tech`'s fallback scan hands
  # the name to whichever tech `TECHS` happens to reach first, i.e. the
  # catalog's insertion order decides a user-visible answer.
  #
  # That is not a theoretical hazard: the split into per-language catalog
  # files reordered insertion, and the three aliases whose winner it would
  # have silently changed had to be pinned after the fact.
  #
  # **Every ambiguous alias belongs here.** The table is consulted before the
  # order-dependent scan, so a pinned alias resolves the same way whatever
  # order `TECHS` is built in — which is what makes the catalog's ordering a
  # free implementation detail rather than a behavioural contract. Thirteen
  # aliases were still resolving by luck; they are pinned below to the tech
  # they already resolved to, so this is not a behaviour change.
  # `spec/unit_test/techs/alias_resolution_spec.cr` fails if a new ambiguous
  # alias appears without a pin, which turns "somebody has to notice" into
  # "somebody has to decide".
  #
  # An alias that is *also* a tech key (`kong`) needs no pin: the exact-key
  # pass runs first and only one key can match it.
  #
  # Keys must be lowercase (the lookup downcases its input).
  AMBIGUOUS_ALIAS_WINNERS = {
    # C++ / Lua / Python / PHP CLI argument parsers.
    "abseil"   => "cpp_cli",
    "argparse" => "cpp_cli",
    "getopt"   => "cpp_cli",
    # Crystal / Elixir / Ruby.
    "optionparser" => "crystal_cli",
    # JS / Rust.
    "getopts" => "js_cli",
    # Crystal / Go stdlib HTTP servers.
    "http"     => "crystal_http",
    "std/http" => "crystal_http",
    # Dart / Python stdlib HTTP servers.
    "httpserver" => "dart_http",
    # JVM CLI parsers, claimed by the Groovy, Java and Kotlin CLI analyzers.
    "commons-cli" => "groovy_cli",
    "jcommander"  => "groovy_cli",
    "picocli"     => "groovy_cli",
    # Java / Kotlin. Worth revisiting on its own merits — a Kotlin Spring
    # project asking for `-t spring` gets the Java analyzer — but that is a
    # behaviour question, not this table's job to change silently.
    "spring" => "java_spring",
    # Rust / Zig.
    "clap" => "zig_cli",
    # Java / Scala.
    "play"           => "scala_play",
    "play-framework" => "scala_play",
  }

  def self.similar_to_tech(word)
    w = word.to_s

    # Accept canonical tech keys exactly (e.g. js_fastify)
    TECHS.each_key do |key|
      return key.to_s if key.to_s == w
    end

    # Fall back to alias lookup. Compare case-insensitively on both sides so
    # mixed-case aliases (e.g. "BaseHTTPRequestHandler", "WEBrick::HTTPServer")
    # still resolve — downcasing only the user input left them permanently dead.
    lowered = w.downcase
    if pinned = AMBIGUOUS_ALIAS_WINNERS[lowered]?
      return pinned
    end
    TECHS.each do |key, value|
      similar = value[:similar]
      next unless similar.is_a?(Array)
      if similar.any? { |alias_name| alias_name.downcase == lowered }
        return key.to_s
      end
    end

    ""
  end

  def self.context_supported?(tech : String, feature : String) : Bool
    case feature
    when "callee"
      CALLEE_SUPPORTED_TECHS.includes?(tech)
    when "guards"
      AI_CONTEXT_GUARD_SUPPORTED_TECHS.includes?(tech)
    when "sinks", "validators", "signals"
      language_tech?(tech)
    else
      false
    end
  end

  def self.language_tech?(tech : String) : Bool
    TECHS.each do |key, info|
      next unless key.to_s == tech
      return info.has_key?(:language)
    end

    false
  end
end

if __FILE__ == PROGRAM_NAME
  # When running this file directly (e.g., `crystal run src/techs/techs.cr`),
  # print the TECHS catalog as JSON. This block does not run when the file is
  # required from other code (e.g., Noir's main application).
  puts NoirTechs::TECHS.to_json
end
