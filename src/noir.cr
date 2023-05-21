require "./cmd/cmd.cr"
require "./detector/detector.cr"
require "./identify/identify.cr"

module Noir
  VERSION = "0.1.0"
end

class NoirRunner
  @options : Hash(Symbol, String)

  def initialize(options)
    @options = options
  end

  def run
    puts @options[:format]
  end
end

app = NoirRunner.new cmd()
app.run