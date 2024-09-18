require "./analyzers/*"
require "./analyzers/file_analyzers/*"

def initialize_analyzers(logger : NoirLogger)
  # Initializing analyzers
  analyzers = {} of String => Proc(Hash(String, YAML::Any), Array(Endpoint))

  # Mapping analyzers to their respective functions
  analyzers["c#-aspnet-mvc"] = ->analyzer_cs_aspnet_mvc(Hash(String, YAML::Any))
  analyzers["crystal_kemal"] = ->analyzer_crystal_kemal(Hash(String, YAML::Any))
  analyzers["crystal_lucky"] = ->analyzer_crystal_lucky(Hash(String, YAML::Any))
  analyzers["elixir_phoenix"] = ->analyzer_elixir_phoenix(Hash(String, YAML::Any))
  analyzers["go_beego"] = ->analyzer_go_beego(Hash(String, YAML::Any))
  analyzers["go_echo"] = ->analyzer_go_echo(Hash(String, YAML::Any))
  analyzers["go_fiber"] = ->analyzer_go_fiber(Hash(String, YAML::Any))
  analyzers["go_gin"] = ->analyzer_go_gin(Hash(String, YAML::Any))
  analyzers["har"] = ->analyzer_har(Hash(String, YAML::Any))
  analyzers["java_armeria"] = ->analyzer_armeria(Hash(String, YAML::Any))
  analyzers["java_jsp"] = ->analyzer_jsp(Hash(String, YAML::Any))
  analyzers["java_spring"] = ->analyzer_java_spring(Hash(String, YAML::Any))
  analyzers["js_express"] = ->analyzer_express(Hash(String, YAML::Any))
  analyzers["js_restify"] = ->analyzer_restify(Hash(String, YAML::Any))
  analyzers["kotlin_spring"] = ->analyzer_kotlin_spring(Hash(String, YAML::Any))
  analyzers["oas2"] = ->analyzer_oas2(Hash(String, YAML::Any))
  analyzers["oas3"] = ->analyzer_oas3(Hash(String, YAML::Any))
  analyzers["php_pure"] = ->analyzer_php_pure(Hash(String, YAML::Any))
  analyzers["python_django"] = ->analyzer_python_django(Hash(String, YAML::Any))
  analyzers["python_fastapi"] = ->analyzer_python_fastapi(Hash(String, YAML::Any))
  analyzers["python_flask"] = ->analyzer_python_flask(Hash(String, YAML::Any))
  analyzers["raml"] = ->analyzer_raml(Hash(String, YAML::Any))
  analyzers["ruby_hanami"] = ->analyzer_ruby_hanami(Hash(String, YAML::Any))
  analyzers["ruby_rails"] = ->analyzer_ruby_rails(Hash(String, YAML::Any))
  analyzers["ruby_sinatra"] = ->analyzer_ruby_sinatra(Hash(String, YAML::Any))
  analyzers["rust_axum"] = ->analyzer_rust_axum(Hash(String, YAML::Any))
  analyzers["rust_rocket"] = ->analyzer_rust_rocket(Hash(String, YAML::Any))

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
