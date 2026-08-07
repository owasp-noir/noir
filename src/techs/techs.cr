require "json"
require "./catalog/*"

module NoirTechs
  CALLEE_SUPPORTED_TECHS = [
    "android", "ios",
    "cpp_crow", "cpp_drogon", "cpp_httplib", "cpp_oatpp",
    "clojure_compojure", "clojure_pedestal", "clojure_reitit",
    "crystal_amber", "crystal_grip", "crystal_kemal", "crystal_lucky", "crystal_marten",
    "cs_aspnet_core_mvc", "cs_aspnet_core_minimal_api", "cs_aspnet_mvc", "cs_carter", "cs_fastendpoints", "cs_httplistener",
    "dart_alfred", "dart_angel3", "dart_get_server", "dart_frog", "dart_serverpod", "dart_shelf",
    "elixir_bandit", "elixir_phoenix", "elixir_plug",
    "fs_giraffe",
    "go_beego", "go_chi", "go_echo", "go_fasthttp", "go_fiber", "go_gf", "go_gin", "go_http",
    "go_gozero", "go_goyave", "go_hertz", "go_httprouter", "go_huma", "go_iris", "go_mux", "go_pocketbase", "go_restful",
    "groovy_grails",
    "haskell_scotty", "haskell_servant", "haskell_yesod",
    "java_armeria", "java_dropwizard", "java_httpserver", "java_jaxrs", "java_javalin", "java_micronaut",
    "java_play", "java_quarkus", "java_spark", "java_spring", "java_struts2", "java_vertx", "java_wicket",
    "js_adonisjs", "js_apollo", "js_astro", "js_elysia", "js_express", "js_fastify",
    "js_fresh", "js_hapi", "js_hono", "js_koa", "js_nestjs", "js_nextjs",
    "js_nitro", "js_nuxtjs", "js_remix", "js_restify", "js_sveltekit",
    "kotlin_http4k", "kotlin_ktor", "kotlin_spring",
    "lua_lapis", "lua_lor",
    "perl_catalyst", "perl_dancer2", "perl_mojolicious",
    "php_cakephp", "php_codeigniter", "php_hyperf", "php_laminas", "php_laravel", "php_lumen", "php_pure", "php_slim", "php_symfony", "php_thinkphp", "php_yii",
    "python_aiohttp", "python_bottle", "python_django", "python_django_ninja", "python_falcon", "python_fastapi",
    "python_flask", "python_litestar", "python_pyramid", "python_quart", "python_robyn", "python_sanic", "python_starlette", "python_tornado", "python_http_server",
    "ruby_grape", "ruby_hanami", "ruby_rails", "ruby_roda", "ruby_sinatra", "ruby_webrick",
    "rust_actix_web", "rust_axum", "rust_gotham", "rust_loco", "rust_poem",
    "rust_rocket", "rust_rwf", "rust_salvo", "rust_tide", "rust_warp",
    "scala_akka", "scala_http4s", "scala_play", "scala_scalatra", "scala_tapir", "scala_zio_http",
    "swift_hummingbird", "swift_kitura", "swift_vapor",
    "ts_nestjs", "ts_tanstack_router", "ts_trpc",
    "zig_jetzig", "zig_zap", "zig_http", "zig_httpz", "zig_tokamak",
    "r_plumber",
  ]

  AI_CONTEXT_GUARD_SUPPORTED_TECHS = [
    "android", "ios",
    "crystal_amber", "crystal_grip", "crystal_kemal", "crystal_lucky", "crystal_marten",
    "cs_aspnet_core_mvc", "cs_aspnet_core_minimal_api", "cs_aspnet_mvc", "cs_carter", "cs_fastendpoints",
    "elixir_bandit", "elixir_phoenix", "elixir_plug",
    "go_beego", "go_chi", "go_echo", "go_fasthttp", "go_fiber", "go_gf", "go_gin", "go_http", "go_gozero", "go_goyave", "go_hertz", "go_iris", "go_mux", "go_restful",
    "java_armeria", "java_jsp", "java_play", "java_spring", "java_vertx",
    "js_express", "js_fastify", "js_hono", "js_koa", "js_nestjs", "js_nuxtjs", "js_restify",
    "kotlin_ktor", "kotlin_spring",
    "perl_catalyst", "perl_dancer2", "perl_mojolicious",
    "php_cakephp", "php_codeigniter", "php_laminas", "php_laravel", "php_pure", "php_slim", "php_symfony", "php_thinkphp", "php_yii",
    "python_django", "python_fastapi", "python_flask", "python_quart", "python_sanic", "python_tornado",
    "ruby_grape", "ruby_hanami", "ruby_rails", "ruby_roda", "ruby_sinatra", "ruby_webrick",
    "rust_actix_web", "rust_axum", "rust_gotham", "rust_loco", "rust_rocket", "rust_rwf", "rust_tide", "rust_warp",
    "scala_akka", "scala_http4s", "scala_play", "scala_scalatra", "scala_tapir",
    "swift_hummingbird", "swift_kitura", "swift_vapor",
    "ts_nestjs",
    "r_plumber",
  ]

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
