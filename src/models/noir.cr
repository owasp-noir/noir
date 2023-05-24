require "../detector/detector.cr"
require "../identify/identify.cr"

class NoirRunner
  @options : Hash(Symbol, String)
  @techs : Array(String)

  def initialize(options)
    @options = options
    @techs = [] of String
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

  def run
    puts @techs
  end

  def detect
    @techs = detect_tech options[:base]
  end
end
