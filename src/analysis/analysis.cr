require "./analyzer/*"

def initialize_analyzers
  analyzers = {} of String => Proc(Hash(Symbol, String), Array(Endpoint))
  analyzers["ruby_rails"] = ->analyzer_rails(Hash(Symbol, String))
  
  analyzers
end

def analysis_endpoints(options : Hash(Symbol, String), techs)
  result = [] of Endpoint
  analyzer = initialize_analyzers
  techs.each do |tech|
    result = result + analyzer[tech].call(options)
  end

  result
end
