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
    {"php_pure", Php::Php},
    {"python_django", Python::Django},
    {"python_fastapi", Python::FastAPI},
    {"python_flask", Python::Flask},
    {"raml", Specification::RAML},
    {"ruby_hanami", Ruby::Hanami},
    {"ruby_rails", Ruby::Rails},
    {"ruby_sinatra", Ruby::Sinatra},
    {"rust_axum", Rust::Axum},
    {"rust_rocket", Rust::Rocket},
  ])

  logger.success "#{analyzers.size} Analyzers initialized"
  logger.debug "Analyzers:"
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
  if options["url"] != ""
    logger.sub "➔ File analyzer initialized and #{file_analyzer.hooks_count} hooks loaded"
  end

  logger.info "Analysis Started"
  logger.sub "➔ Code Analyzer: #{techs.size} in use"

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

  logger.sub "➔ Found #{result.size} endpoints"
  result
end
