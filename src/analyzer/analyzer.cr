require "./analyzers/*"

def initialize_analyzers(logger : NoirLogger)
  analyzers = {} of String => Proc(Hash(Symbol, String), Array(Endpoint))
  analyzers["ruby_rails"] = ->analyzer_rails(Hash(Symbol, String))
  analyzers["ruby_sinatra"] = ->analyzer_sinatra(Hash(Symbol, String))
  analyzers["ruby_hanami"] = ->analyzer_hanami(Hash(Symbol, String))
  analyzers["java_spring"] = ->analyzer_spring(Hash(Symbol, String))
  analyzers["kotlin_spring"] = ->analyzer_spring(Hash(Symbol, String))
  analyzers["java_armeria"] = ->analyzer_armeria(Hash(Symbol, String))
  analyzers["php_pure"] = ->analyzer_php_pure(Hash(Symbol, String))
  analyzers["go_echo"] = ->analyzer_go_echo(Hash(Symbol, String))
  analyzers["go_gin"] = ->analyzer_go_gin(Hash(Symbol, String))
  analyzers["python_flask"] = ->analyzer_flask(Hash(Symbol, String))
  analyzers["python_fastapi"] = ->analyzer_fastapi(Hash(Symbol, String))
  analyzers["python_django"] = ->analyzer_django(Hash(Symbol, String))
  analyzers["js_express"] = ->analyzer_express(Hash(Symbol, String))
  analyzers["crystal_kemal"] = ->analyzer_kemal(Hash(Symbol, String))
  analyzers["oas2"] = ->analyzer_oas2(Hash(Symbol, String))
  analyzers["oas3"] = ->analyzer_oas3(Hash(Symbol, String))
  analyzers["raml"] = ->analyzer_raml(Hash(Symbol, String))
  analyzers["java_jsp"] = ->analyzer_jsp(Hash(Symbol, String))
  analyzers["c#-aspnet-mvc"] = ->analyzer_cs_aspnet_mvc(Hash(Symbol, String))
  analyzers["rust_axum"] = ->analyzer_rust_axum(Hash(Symbol, String))

  logger.info_sub "#{analyzers.size} Analyzers initialized"
  logger.debug "Analyzers:"
  analyzers.each do |key, _|
    logger.debug_sub "#{key} initialized"
  end
  analyzers
end

def analysis_endpoints(options : Hash(Symbol, String), techs, logger : NoirLogger)
  result = [] of Endpoint
  logger.system "Starting analysis of endpoints."

  analyzer = initialize_analyzers logger
  logger.info_sub "Analysis to #{techs.size} technologies"

  if (techs.includes? "java_spring") && (techs.includes? "kotlin_spring")
    techs.delete("kotlin_spring")
  end

  techs.each do |tech|
    if analyzer.has_key?(tech)
      if NoirTechs.similar_to_tech(options[:exclude_techs]).includes?(tech)
        logger.info_sub "Skipping #{tech} analysis"
        next
      end
      result = result + analyzer[tech].call(options)
    end
  end

  logger.info_sub "#{result.size} endpoints found"
  result
end
