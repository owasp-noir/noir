require "../../spec_helper"
require "../../../src/cli/legacy"

# These specs exercise the slim, side-effect-free portions of the v1 CLI
# routing layer — terminal-flag rewriting, command lookup, and the
# fallback to `scan` for bare-flag (v0) invocations.
describe "Noir::CLI::Legacy.rewrite" do
  it "rewrites --list-techs to `list techs`" do
    Noir::CLI::Legacy.rewrite(["--list-techs"]).should eq(["list", "techs"])
  end

  it "rewrites --list-taggers to `list taggers`" do
    Noir::CLI::Legacy.rewrite(["--list-taggers"]).should eq(["list", "taggers"])
  end

  it "rewrites --build-info to `version --verbose`" do
    Noir::CLI::Legacy.rewrite(["--build-info"]).should eq(["version", "--verbose"])
  end

  it "rewrites --help-all to `help`" do
    Noir::CLI::Legacy.rewrite(["--help-all"]).should eq(["help"])
  end

  it "rewrites --generate-completion SHELL to `completion SHELL`" do
    Noir::CLI::Legacy.rewrite(["--generate-completion", "zsh"]).should eq(["completion", "zsh"])
  end

  it "leaves non-terminal v0 invocations untouched" do
    argv = ["-b", "./app", "--passive"]
    Noir::CLI::Legacy.rewrite(argv).should eq(argv)
  end

  it "matches terminal flags even when they appear after positional args" do
    Noir::CLI::Legacy.rewrite(["-b", "./app", "--list-techs"]).should eq(["list", "techs"])
  end
end

describe "Noir::CLI::KNOWN_COMMANDS" do
  it "includes every v1 verb so the router can dispatch them" do
    %w[scan list cache config rules completion version help].each do |verb|
      Noir::CLI::KNOWN_COMMANDS.includes?(verb).should be_true
    end
  end
end
