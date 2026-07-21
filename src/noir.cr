require "option_parser"
require "colorize"

module Noir
  VERSION = "1.2.1"
end

require "./cli/router"

Noir::CLI::Router.dispatch(ARGV)
