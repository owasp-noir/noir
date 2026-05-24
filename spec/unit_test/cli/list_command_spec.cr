require "../../spec_helper"
require "../../../src/cli/commands/list"

describe Noir::CLI::ListCommand do
  describe ".parse_argv" do
    it "returns subject=nil, help=false when called with no args" do
      parsed = Noir::CLI::ListCommand.parse_argv([] of String)
      parsed.subject.should be_nil
      parsed.help.should be_false
    end

    it "captures the first positional as the subject" do
      Noir::CLI::ListCommand.parse_argv(["techs"]).subject.should eq("techs")
      Noir::CLI::ListCommand.parse_argv(["taggers"]).subject.should eq("taggers")
      Noir::CLI::ListCommand.parse_argv(["formats"]).subject.should eq("formats")
    end

    it "first positional wins over subsequent positionals" do
      Noir::CLI::ListCommand.parse_argv(["techs", "extra"]).subject.should eq("techs")
    end

    it "flags -h / --help anywhere in argv" do
      Noir::CLI::ListCommand.parse_argv(["-h"]).help.should be_true
      Noir::CLI::ListCommand.parse_argv(["--help"]).help.should be_true
      Noir::CLI::ListCommand.parse_argv(["techs", "--help"]).help.should be_true
    end
  end

  describe "SUBJECTS constant" do
    it "lists every subject the run dispatcher handles" do
      Noir::CLI::ListCommand::SUBJECTS.should eq(%w[techs taggers formats])
    end
  end

  describe ".print_help" do
    it "names every supported subject" do
      io = IO::Memory.new
      Noir::CLI::ListCommand.print_help(io)
      out = io.to_s
      %w[techs taggers formats].each { |subject| out.should contain(subject) }
      # Legacy aliases should be cross-referenced so users who knew the
      # v0 names can find the v1 verb.
      out.should contain("--list-techs")
      out.should contain("--list-taggers")
    end
  end
end
