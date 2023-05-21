require "./cmd/cmd.cr"
require "./detector/detector.cr"
require "./identify/identify.cr"

module Noir
  VERSION = "0.1.0"

  class App
    @options : Hash(Symbol, String)

    def initialize(options)
      @options = options
    end

    def run
      puts @options[:format]
    end
  end
end

app = Noir::App.new cmd()
app.run