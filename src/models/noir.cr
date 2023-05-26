require "../detector/detector.cr"
require "../analysis/analysis.cr"
require "./endpoint.cr"
require "json"

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

  def report
    case options[:format]
    when "json"
      # TODO // puts @endpoints.to_json
    when "har"
      # TODO
    when "curl"
      @endpoints.each do |endpoint|
        puts "curl -i -k -X #{endpoint.method} #{endpoint.url}}"
      end
    else
      @endpoints.each do |endpoint|
        puts "curl -i -k -X #{endpoint.method} #{endpoint.url}}"
      end
    end
  end
end
