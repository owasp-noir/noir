require "../../spec_helper"
require "../../../src/cli/commands/completion"

describe Noir::CLI::CompletionCommand do
  describe ".parse_argv" do
    it "returns shell=nil, help=false when called with no args" do
      parsed = Noir::CLI::CompletionCommand.parse_argv([] of String)
      parsed.shell.should be_nil
      parsed.help.should be_false
    end

    it "captures the first positional as the shell name" do
      Noir::CLI::CompletionCommand.parse_argv(["zsh"]).shell.should eq("zsh")
      Noir::CLI::CompletionCommand.parse_argv(["bash"]).shell.should eq("bash")
      Noir::CLI::CompletionCommand.parse_argv(["fish"]).shell.should eq("fish")
      Noir::CLI::CompletionCommand.parse_argv(["elvish"]).shell.should eq("elvish")
    end

    it "first positional wins over subsequent positionals" do
      # `noir completion zsh ./extra` is acceptable — extras are
      # ignored, not silently promoted to the shell slot.
      parsed = Noir::CLI::CompletionCommand.parse_argv(["zsh", "extra"])
      parsed.shell.should eq("zsh")
    end

    it "flags -h / --help anywhere in argv" do
      Noir::CLI::CompletionCommand.parse_argv(["-h"]).help.should be_true
      Noir::CLI::CompletionCommand.parse_argv(["--help"]).help.should be_true
      Noir::CLI::CompletionCommand.parse_argv(["zsh", "--help"]).help.should be_true
    end
  end

  describe ".print_help" do
    it "names every supported shell" do
      io = IO::Memory.new
      Noir::CLI::CompletionCommand.print_help(io)
      out = io.to_s
      %w[zsh bash fish elvish].each { |shell| out.should contain(shell) }
      # Install hints should match the actual filenames noir produces.
      out.should contain("_noir")
      out.should contain("bash_completion.d/noir")
      out.should contain("noir.fish")
      out.should contain("noir.elv")
    end
  end

  describe "SHELLS constant" do
    it "lists every shell the run dispatcher actually handles" do
      Noir::CLI::CompletionCommand::SHELLS.should eq(%w[zsh bash fish elvish])
    end
  end
end
