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

    it "rejects a surplus positional instead of dropping it" do
      # `noir completion zsh bash` used to emit the zsh script and exit
      # 0, leaving the bash completion the user asked for unwritten.
      parsed = Noir::CLI::CompletionCommand.parse_argv(["zsh", "bash"])
      parsed.shell.should eq("zsh")
      parsed.error.should eq("Unexpected argument: bash. Usage: noir completion <shell>")
    end

    it "pluralizes and lists every surplus positional" do
      parsed = Noir::CLI::CompletionCommand.parse_argv(["zsh", "bash", "fish"])
      parsed.error.should eq("Unexpected arguments: bash, fish. Usage: noir completion <shell>")
    end

    it "rejects an unknown flag instead of ignoring it" do
      parsed = Noir::CLI::CompletionCommand.parse_argv(["zsh", "--oops"])
      parsed.error.should eq("Unknown option: --oops. Run `noir completion --help`.")
    end

    it "accepts the router's global flags" do
      parsed = Noir::CLI::CompletionCommand.parse_argv(["--no-color", "zsh", "--no-spinner"])
      parsed.shell.should eq("zsh")
      parsed.error.should be_nil
    end

    it "reports no error for a well-formed invocation" do
      Noir::CLI::CompletionCommand.parse_argv(["zsh"]).error.should be_nil
      Noir::CLI::CompletionCommand.parse_argv([] of String).error.should be_nil
    end

    it "flags -h / --help anywhere in argv" do
      Noir::CLI::CompletionCommand.parse_argv(["-h"]).help.should be_true
      Noir::CLI::CompletionCommand.parse_argv(["--help"]).help.should be_true
      Noir::CLI::CompletionCommand.parse_argv(["zsh", "--help"]).help.should be_true
    end

    it "lowercases the shell name so `ZSH`/`Fish` still dispatch" do
      Noir::CLI::CompletionCommand.parse_argv(["ZSH"]).shell.should eq("zsh")
      Noir::CLI::CompletionCommand.parse_argv(["Fish"]).shell.should eq("fish")
      Noir::CLI::CompletionCommand.parse_argv(["ELVISH"]).shell.should eq("elvish")
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
      out.should contain("bash-completion/completions/noir")
      out.should contain("noir.fish")
      out.should contain("noir.elv")
    end

    it "gives copy-pasteable install hints that work on macOS / fresh homes" do
      io = IO::Memory.new
      Noir::CLI::CompletionCommand.print_help(io)
      out = io.to_s
      # Every install path is preceded by an mkdir -p so copy-paste never
      # fails on a directory that doesn't exist yet (finding: bash on macOS
      # + elvish's lib dir on a fresh $HOME).
      out.should contain("mkdir -p ~/.local/share/bash-completion/completions")
      out.should contain("mkdir -p ~/.config/elvish/lib")
    end
  end

  describe "SHELLS constant" do
    it "lists every shell the run dispatcher actually handles" do
      Noir::CLI::CompletionCommand::SHELLS.should eq(%w[zsh bash fish elvish])
    end
  end
end
