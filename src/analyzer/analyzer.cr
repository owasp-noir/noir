require "./analyzers/**"
require "./analyzers/file_analyzers/*"

macro define_analyzers(analyzers)
  {% for analyzer in analyzers %}
    analyzers[{{analyzer[0].id.stringify}}] = ->(options : Hash(String, YAML::Any)) do
      instance = Analyzer::{{analyzer[1].id}}.new(options)
      instance.analyze
    end
  {% end %}
end

def initialize_analyzers(logger : NoirLogger)
  # Initializing analyzers
  analyzers = {} of String => Proc(Hash(String, YAML::Any), Array(Endpoint))

  # Mapping analyzers to their respective functions
  define_analyzers([
    {"c#-aspnet-mvc", CSharp::AspNetMvc},
    {"c#-aspnet-core-mvc", CSharp::AspNetCoreMvc},
    {"crystal_amber", Crystal::Amber},
    {"crystal_grip", Crystal::Grip},
    {"crystal_kemal", Crystal::Kemal},
    {"crystal_lucky", Crystal::Lucky},
    {"crystal_marten", Crystal::Marten},
    {"elixir_phoenix", Elixir::Phoenix},
    {"elixir_plug", Elixir::Plug},
    {"go_beego", Go::Beego},
    {"go_echo", Go::Echo},
    {"go_fasthttp", Go::Fasthttp},
    {"go_fiber", Go::Fiber},
    {"go_gin", Go::Gin},
    {"go_chi", Go::Chi},
    {"go_gozero", Go::GoZero},
    {"go_mux", Go::Mux},
    {"har", Specification::Har},
    {"java_armeria", Java::Armeria},
    {"java_jsp", Java::Jsp},
    {"java_spring", Java::Spring},
    {"java_vertx", Java::Vertx},
    {"js_express", Javascript::Express},
    {"js_fastify", Javascript::Fastify},
    {"js_koa", Javascript::Koa},
    {"js_nestjs", Javascript::Nestjs},
    {"js_restify", Javascript::Restify},
    {"kotlin_spring", Kotlin::Spring},
    {"kotlin_ktor", Kotlin::Ktor},
    {"oas2", Specification::Oas2},
    {"oas3", Specification::Oas3},
    {"postman", Specification::Postman},
    {"raml", Specification::RAML},
    {"zap_sites_tree", Specification::ZapSitesTree},
    {"php_pure", Php::Php},
    {"php_laravel", Php::Laravel},
    {"php_symfony", Php::Symfony},
    {"python_django", Python::Django},
    {"python_fastapi", Python::FastAPI},
    {"python_flask", Python::Flask},
    {"python_sanic", Python::Sanic},
    {"python_tornado", Python::Tornado},
    {"ruby_hanami", Ruby::Hanami},
    {"ruby_rails", Ruby::Rails},
    {"ruby_sinatra", Ruby::Sinatra},
    {"rust_axum", Rust::Axum},
    {"rust_rocket", Rust::Rocket},
    {"rust_actix_web", Rust::ActixWeb},
    {"rust_loco", Rust::Loco},
    {"rust_rwf", Rust::Rwf},
    {"rust_tide", Rust::Tide},
    {"rust_warp", Rust::Warp},
    {"rust_gotham", Rust::Gotham},
    {"ai", AI::Unified},
  ])

  logger.debug "#{analyzers.size} Analyzers initialized"
  analyzers.each do |key, _|
    logger.debug_sub "#{key} initialized"
  end
  analyzers
end

def analysis_endpoints(options : Hash(String, YAML::Any), techs, logger : NoirLogger)
  result = [] of Endpoint
  file_analyzer = FileAnalyzer.new options
  logger.info "Initializing analyzers"

  analyzer = initialize_analyzers logger

  logger.verbose "Loaded #{analyzer.size} analyzers"

  logger.info "Analysis Started"
  logger.sub "➔ Code Analyzer: #{techs.size} in use"

  if (options["ai_provider"] != "") && (options["ai_model"] != "")
    logger.sub "➔ AI Analyzer: Server=#{options["ai_provider"]}, Model=#{options["ai_model"]}"
    techs << "ai"
  elsif (options["ollama"] != "") && (options["ollama_model"] != "")
    logger.sub "➔ AI Analyzer: Ollama in use"
    techs << "ai"
  end

  techs.each do |tech|
    next unless analyzer.has_key?(tech)
    result = result + analyzer[tech].call(options)
  end

  if options["url"] != ""
    logger.sub "➔ File-based Analyzer: #{file_analyzer.hooks_count} hook in use"
    result = result + file_analyzer.analyze
  end

  logger.info "Found #{result.size} endpoints"
  result
end

def join_paths(*paths : String) : String
  File.join(paths)
end
