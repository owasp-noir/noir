require "../detector/detector.cr"
require "../analysis/analysis.cr"
require "./endpoint.cr"

class NoirRunner
  @options : Hash(Symbol, String)
  @techs : Array(String)
  @endpoints : Array(Endpoint)

  def initialize(options)
    @options = options
    @techs = [] of String
    @endpoints = [] of Endpoint
    if options[:techs].size > 0
      @techs = options[:techs].split(",")
    end
  end

  def options
    @options
  end

  def techs
    @techs
  end

  def endpoints
    @endpoints
  end

  def run
    puts @techs
  end

  def detect
    @techs = detect_tech options[:base]
  end

  def analyze
    @endpoints = analysis_endpoints options, @techs
  end
end
