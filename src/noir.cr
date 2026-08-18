require "option_parser"
require "colorize"

module Noir
  VERSION = "1.3.0"
end

require "./cli/router"

Noir::CLI::Router.dispatch(ARGV)
