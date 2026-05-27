require "../../spec_helper"
require "../../../src/cli/commands/help"

describe Noir::CLI::HelpCommand do
  describe ".route_for" do
    it "routes empty argv to TopLevel" do
      Noir::CLI::HelpCommand.route_for([] of String).should eq(Noir::CLI::HelpCommand::Route::TopLevel)
    end

    it "routes recognised commands to their matching Route variant" do
      {
        "scan"       => Noir::CLI::HelpCommand::Route::Scan,
        "list"       => Noir::CLI::HelpCommand::Route::List,
        "cache"      => Noir::CLI::HelpCommand::Route::Cache,
        "config"     => Noir::CLI::HelpCommand::Route::Config,
        "rules"      => Noir::CLI::HelpCommand::Route::Rules,
        "completion" => Noir::CLI::HelpCommand::Route::Completion,
        "version"    => Noir::CLI::HelpCommand::Route::Version,
        "help"       => Noir::CLI::HelpCommand::Route::Help,
      }.each do |cmd, expected|
        Noir::CLI::HelpCommand.route_for([cmd]).should eq(expected)
      end
    end

    it "routes unknown commands to Route::Unknown so run can die" do
      Noir::CLI::HelpCommand.route_for(["bogus"]).should eq(Noir::CLI::HelpCommand::Route::Unknown)
      Noir::CLI::HelpCommand.route_for(["--unknown-flag"]).should eq(Noir::CLI::HelpCommand::Route::Unknown)
    end

    it "ignores trailing positionals when picking the route" do
      # `noir help scan extra` is treated the same as `noir help scan`.
      # That's intentional — extras are not silently routed elsewhere.
      Noir::CLI::HelpCommand.route_for(["scan", "extra"]).should eq(Noir::CLI::HelpCommand::Route::Scan)
    end
  end

  describe "KNOWN_HELP_TARGETS constant" do
    it "lists exactly the subcommands route_for recognises (minus Unknown)" do
      Noir::CLI::HelpCommand::KNOWN_HELP_TARGETS.should eq(
        %w[scan list cache config rules completion version help]
      )
    end

    it "stays in sync with the Route enum (each target has a Route variant)" do
      # Guard against a target being added to KNOWN_HELP_TARGETS but
      # not wired into Route::… — the enum lookup will return nil for
      # any unrecognised name.
      Noir::CLI::HelpCommand::KNOWN_HELP_TARGETS.each do |target|
        next if target == "help" # mapped to Route::Help via case branch
        variant = target.capitalize
        Noir::CLI::HelpCommand::Route.parse?(variant).should_not be_nil
      end
    end
  end

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
      out.should contain("-v, --version")
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
