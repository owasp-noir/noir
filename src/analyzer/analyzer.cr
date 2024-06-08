require "./analyzers/*"
require "./analyzers/file_analyzers/*"

def initialize_analyzers(logger : NoirLogger)
  # Initializing analyzers
  analyzers = {} of String => Proc(Hash(String, String), Array(Endpoint))

  # Mapping analyzers to their respective functions
  analyzers["c#-aspnet-mvc"] = ->analyzer_cs_aspnet_mvc(Hash(String, String))
  analyzers["crystal_kemal"] = ->analyzer_crystal_kemal(Hash(String, String))
  analyzers["crystal_lucky"] = ->analyzer_crystal_lucky(Hash(String, String))
  analyzers["elixir_phoenix"] = ->analyzer_elixir_phoenix(Hash(String, String))
  analyzers["go_beego"] = ->analyzer_go_beego(Hash(String, String))
  analyzers["go_echo"] = ->analyzer_go_echo(Hash(String, String))
  analyzers["go_fiber"] = ->analyzer_go_fiber(Hash(String, String))
  analyzers["go_gin"] = ->analyzer_go_gin(Hash(String, String))
  analyzers["har"] = ->analyzer_har(Hash(String, String))
  analyzers["java_armeria"] = ->analyzer_armeria(Hash(String, String))
  analyzers["java_jsp"] = ->analyzer_jsp(Hash(String, String))
  analyzers["java_spring"] = ->analyzer_java_spring(Hash(String, String))
  analyzers["js_express"] = ->analyzer_express(Hash(String, String))
  analyzers["js_restify"] = ->analyzer_restify(Hash(String, String))
  analyzers["kotlin_spring"] = ->analyzer_kotlin_spring(Hash(String, String))
  analyzers["oas2"] = ->analyzer_oas2(Hash(String, String))
  analyzers["oas3"] = ->analyzer_oas3(Hash(String, String))
  analyzers["php_pure"] = ->analyzer_php_pure(Hash(String, String))
  analyzers["python_django"] = ->analyzer_django(Hash(String, String))
  analyzers["python_fastapi"] = ->analyzer_fastapi(Hash(String, String))
  analyzers["python_flask"] = ->analyzer_flask(Hash(String, String))
  analyzers["raml"] = ->analyzer_raml(Hash(String, String))
  analyzers["ruby_hanami"] = ->analyzer_ruby_hanami(Hash(String, String))
  analyzers["ruby_rails"] = ->analyzer_ruby_rails(Hash(String, String))
  analyzers["ruby_sinatra"] = ->analyzer_ruby_sinatra(Hash(String, String))
  analyzers["rust_axum"] = ->analyzer_rust_axum(Hash(String, String))
  analyzers["rust_rocket"] = ->analyzer_rust_rocket(Hash(String, String))

  logger.info_sub "#{analyzers.size} Analyzers initialized"
  logger.debug "Analyzers:"
  analyzers.each do |key, _|
    logger.debug_sub "#{key} initialized"
  end
  analyzers
end

def analysis_endpoints(options : Hash(String, String), techs, logger : NoirLogger)
  result = [] of Endpoint
  file_analyzer = FileAnalyzer.new options
  logger.system "Initializing analyzers"

  analyzer = initialize_analyzers logger
  if options["url"] != ""
    logger.info_sub "File analyzer initialized and #{file_analyzer.hooks_count} hooks loaded"
  end

  logger.system "Analysis Started"
  logger.info_sub "Code Analyzer: #{techs.size} in use"

  techs.each do |tech|
    if analyzer.has_key?(tech)
      if NoirTechs.similar_to_tech(options["exclude_techs"]).includes?(tech)
        logger.info_sub "Skipping #{tech} analysis"
        next
      end
      result = result + analyzer[tech].call(options)
    end
  end

  if options["url"] != ""
    logger.info_sub "File-based Analyzer: #{file_analyzer.hooks_count} hook in use"
    result = result + file_analyzer.analyze
  end

  logger.info_sub "Found #{result.size} endpoints"
  result
end
