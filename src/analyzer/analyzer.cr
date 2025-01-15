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
    {"crystal_kemal", Crystal::Kemal},
    {"crystal_lucky", Crystal::Lucky},
    {"elixir_phoenix", Elixir::Phoenix},
    {"go_beego", Go::Beego},
    {"go_echo", Go::Echo},
    {"go_fiber", Go::Fiber},
    {"go_gin", Go::Gin},
    {"har", Specification::Har},
    {"java_armeria", Java::Armeria},
    {"java_jsp", Java::Jsp},
    {"java_spring", Java::Spring},
    {"js_express", Javascript::Express},
    {"js_restify", Javascript::Restify},
    {"kotlin_spring", Kotlin::Spring},
    {"oas2", Specification::Oas2},
    {"oas3", Specification::Oas3},
    {"raml", Specification::RAML},
    {"zap_sites_tree", Specification::ZapSitesTree},
    {"php_pure", Php::Php},
    {"python_django", Python::Django},
    {"python_fastapi", Python::FastAPI},
    {"python_flask", Python::Flask},
    {"ruby_hanami", Ruby::Hanami},
    {"ruby_rails", Ruby::Rails},
    {"ruby_sinatra", Ruby::Sinatra},
    {"rust_axum", Rust::Axum},
    {"rust_rocket", Rust::Rocket},
    {"rust_actix_web", Rust::ActixWeb},
    {"ai_ollama", AI::Ollama},
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

  logger.info "Analysis Started"
  logger.sub "➔ Code Analyzer: #{techs.size} in use"

  if (options["ollama"].to_s != "") && (options["ollama_model"].to_s != "")
    logger.sub "➔ AI Analyzer: Ollama in use"
    techs << "ai_ollama"
  end

  techs.each do |tech|
    if analyzer.has_key?(tech)
      if NoirTechs.similar_to_tech(options["exclude_techs"].to_s).includes?(tech)
        logger.sub "➔ Skipping #{tech} analysis"
        next
      end
      result = result + analyzer[tech].call(options)
    end
  end

  if options["url"] != ""
    logger.sub "➔ File-based Analyzer: #{file_analyzer.hooks_count} hook in use"
    result = result + file_analyzer.analyze
  end

  logger.info "Found #{result.size} endpoints"
  result
end
