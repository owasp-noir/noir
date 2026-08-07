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

  def self.techs
    TECHS
  end

  # A handful of aliases are claimed by more than one tech (genuine
  # cross-language library-name ambiguity) and used to resolve by the
  # catalog literal's insertion order. The split into per-language catalog
  # files reordered insertion, so the aliases whose winner that would have
  # silently changed are pinned here instead of implicitly. Keys must be
  # lowercase (the lookup downcases its input).
  AMBIGUOUS_ALIAS_WINNERS = {
    "clap"           => "zig_cli",
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
