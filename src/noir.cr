require "./cmd/cmd.cr"
require "./detector/detector.cr"
require "./identify/identify.cr"

module Noir
  VERSION = "0.1.0"
  OPTIONS = {
    :base => ".",
    :url => "",
    :output => "",
    :format => "plain",
  }

  class App
    def initialize
      @options = OPTIONS
    end

    def run
      puts OPTIONS[:format]
    end
  end
end

app = Noir::App.new
app.run