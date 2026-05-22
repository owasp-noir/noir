require "option_parser"
require "colorize"

module Noir
  VERSION = "0.30.0"
end

require "./cli/router"

Noir::CLI::Router.dispatch(ARGV)
