require "./analyzers/*"

def initialize_analyzers(logger : NoirLogger)
  analyzers = {} of String => Proc(Hash(Symbol, String), Array(Endpoint))
  analyzers["ruby_rails"] = ->analyzer_rails(Hash(Symbol, String))
  analyzers["ruby_sinatra"] = ->analyzer_sinatra(Hash(Symbol, String))
  analyzers["java_spring"] = ->analyzer_spring(Hash(Symbol, String))
  analyzers["php_pure"] = ->analyzer_php_pure(Hash(Symbol, String))
  analyzers["go_echo"] = ->analyzer_go_echo(Hash(Symbol, String))
  analyzers["python_flask"] = ->analyzer_flask(Hash(Symbol, String))
  analyzers["python_django"] = ->analyzer_django(Hash(Symbol, String))
  analyzers["js_express"] = ->analyzer_express(Hash(Symbol, String))
  analyzers["crystal_kemal"] = ->analyzer_kemal(Hash(Symbol, String))

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
