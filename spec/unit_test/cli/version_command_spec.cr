require "../../spec_helper"
require "../../../src/cli/commands/version"

describe Noir::CLI::VersionCommand do
  describe ".parse_argv" do
    it "returns defaults for no args" do
      parsed = Noir::CLI::VersionCommand.parse_argv([] of String)
      parsed.verbose.should be_false
      parsed.help.should be_false
      parsed.unknown.should be_nil
    end

    it "flags -V / --verbose" do
      Noir::CLI::VersionCommand.parse_argv(["-V"]).verbose.should be_true
      Noir::CLI::VersionCommand.parse_argv(["--verbose"]).verbose.should be_true
    end

    it "flags -h / --help" do
      Noir::CLI::VersionCommand.parse_argv(["-h"]).help.should be_true
      Noir::CLI::VersionCommand.parse_argv(["--help"]).help.should be_true
    end

    it "captures the first unknown option for the dispatcher to die on" do
      # `run` calls `die` on the unknown payload — the parser surfaces
      # it so the validation rule is exercisable without exiting.
      parsed = Noir::CLI::VersionCommand.parse_argv(["--bogus"])
      parsed.unknown.should eq("--bogus")
    end

    it "first unknown wins when several are present" do
      parsed = Noir::CLI::VersionCommand.parse_argv(["--bogus", "--also-bogus"])
      parsed.unknown.should eq("--bogus")
    end

    it "treats unknown alongside valid flags consistently" do
      parsed = Noir::CLI::VersionCommand.parse_argv(["--verbose", "--bogus"])
      parsed.verbose.should be_true
      parsed.unknown.should eq("--bogus")
    end
  end

  describe ".print_version" do
    it "prints the bare VERSION when verbose is false" do
      io = IO::Memory.new
      Noir::CLI::VersionCommand.print_version(false, io)
      io.to_s.strip.should eq(Noir::VERSION)
    end

    it "prints build details when verbose is true" do
      io = IO::Memory.new
      Noir::CLI::VersionCommand.print_version(true, io)
      out = io.to_s
      out.should contain("Noir: #{Noir::VERSION}")
      out.should contain("Crystal:")
      out.should contain("LLVM:")
      out.should contain("Target:")
    end
  end

  describe ".print_help" do
    it "explains both --verbose and the v0 aliases" do
      io = IO::Memory.new
      Noir::CLI::VersionCommand.print_help(io)
      out = io.to_s
      out.should contain("--verbose")
      out.should contain("-V")
      out.should contain("--build-info")
      out.should contain("noir -v")
    end
  end
end
