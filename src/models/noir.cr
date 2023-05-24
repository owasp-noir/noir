require "../detector/detector.cr"
require "../identify/identify.cr"

class NoirRunner
  @options : Hash(Symbol, String)
  @techs : Array(String)

  def initialize(options)
    @options = options
    @techs = [] of String
  end

  def options
    @options
  end

  def run
    puts @options[:format]
  end

  def detect
    @techs = detect_tech options[:base]
  end
end
