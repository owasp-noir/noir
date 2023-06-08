require "./analyzer/*"

def initialize_analyzers
  analyzers = {} of String => Proc(Hash(Symbol, String), Array(Endpoint))
  analyzers["ruby_rails"] = ->analyzer_rails(Hash(Symbol, String))
  analyzers["ruby_sinatra"] = ->analyzer_sinatra(Hash(Symbol, String))
  analyzers["java_spring"] = ->analyzer_spring(Hash(Symbol, String))
  analyzers["php_pure"] = ->analyzer_php_pure(Hash(Symbol, String))
  analyzers["go_echo"] = ->analyzer_go_echo(Hash(Symbol, String))
  analyzers["python_flask"] = ->analyzer_flask(Hash(Symbol, String))
  analyzers["python_django"] = ->analyzer_django(Hash(Symbol, String))
  analyzers["js_express"] = ->analyzer_express(Hash(Symbol, String))

  analyzers
end

def analysis_endpoints(options : Hash(Symbol, String), techs)
  result = [] of Endpoint
  analyzer = initialize_analyzers
  techs.each do |tech|
    if analyzer.has_key?(tech)
      result = result + analyzer[tech].call(options)
    end
  end

  result
end
