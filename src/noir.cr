require "option_parser"
require "colorize"

module Noir
  VERSION = "1.4.0"
end

require "./cli/router"

# Crystal 1.22 makes STDOUT/STDERR `exit 141` on a broken pipe before any
# rescue runs. Keep handling it ourselves so `noir ... | head` still exits 0
# (see `Router.dispatch` and `NoirLogger.broken_pipe?`).
{% if IO::FileDescriptor.has_method?("exit_on_broken_pipe=") %}
  STDOUT.exit_on_broken_pipe = false
  STDERR.exit_on_broken_pipe = false
{% end %}

Noir::CLI::Router.dispatch(ARGV)
