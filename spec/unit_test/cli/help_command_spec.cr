require "../../spec_helper"
require "../../../src/cli/commands/help"

describe Noir::CLI::HelpCommand do
  describe ".print_top_level" do
    it "lists every supported command + global flags" do
      io = IO::Memory.new
      banner_sink = IO::Memory.new
      Noir::CLI::HelpCommand.print_top_level(io, banner_sink)
      out = io.to_s
      %w[scan list cache config rules completion version help].each do |cmd|
        out.should contain(cmd)
      end
      out.should contain("--no-color")
      out.should contain("--no-spinner")
      out.should contain("-v, -V, --version")
      out.should contain("-h, --help")
    end

    it "writes the banner to the banner_io and the help body to io" do
      help_sink = IO::Memory.new
      banner_sink = IO::Memory.new
      Noir::CLI::HelpCommand.print_top_level(help_sink, banner_sink)

      # The two streams have different responsibilities — help body
      # goes to STDOUT (machine-pipeable), banner goes to STDERR
      # (decorative). Spec asserts they don't bleed into each other.
      banner_sink.to_s.should contain("N O I R")
      help_sink.to_s.should_not contain("N O I R")
    end
  end
end
