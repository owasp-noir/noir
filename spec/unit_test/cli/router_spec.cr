require "../../spec_helper"
require "colorize"
require "../../../src/cli/common"
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

  it "rewrites -v to the version subcommand (global anywhere in ARGV)" do
    Noir::CLI::Legacy.rewrite(["-v"]).should eq(["version"])
    Noir::CLI::Legacy.rewrite(["scan", "-v"]).should eq(["version"])
    Noir::CLI::Legacy.rewrite(["scan", "./app", "-v"]).should eq(["version"])
  end

  it "rewrites --version the same way as -v" do
    Noir::CLI::Legacy.rewrite(["--version"]).should eq(["version"])
    Noir::CLI::Legacy.rewrite(["list", "techs", "--version"]).should eq(["version"])
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

describe "Noir::CLI.apply_global_color_flag!" do
  # Each spec restores Colorize.enabled and the NO_COLOR env var so
  # later specs see a clean default.
  it "disables Colorize when --no-color is present" do
    saved_env = ENV["NO_COLOR"]?
    ENV.delete("NO_COLOR")
    Colorize.enabled = true

    Noir::CLI.apply_global_color_flag!(["list", "techs", "--no-color"])
    Colorize.enabled?.should be_false
  ensure
    Colorize.enabled = true
    if saved = saved_env
      ENV["NO_COLOR"] = saved
    else
      ENV.delete("NO_COLOR")
    end
  end

  it "disables Colorize when NO_COLOR is set" do
    saved_env = ENV["NO_COLOR"]?
    ENV["NO_COLOR"] = "1"
    Colorize.enabled = true

    Noir::CLI.apply_global_color_flag!(["list", "techs"])
    Colorize.enabled?.should be_false
  ensure
    Colorize.enabled = true
    if saved = saved_env
      ENV["NO_COLOR"] = saved
    else
      ENV.delete("NO_COLOR")
    end
  end

  it "treats NO_COLOR=0 as opt-in (color stays on)" do
    saved_env = ENV["NO_COLOR"]?
    ENV["NO_COLOR"] = "0"
    Colorize.enabled = true

    Noir::CLI.apply_global_color_flag!(["list", "techs"])
    Colorize.enabled?.should be_true
  ensure
    Colorize.enabled = true
    if saved = saved_env
      ENV["NO_COLOR"] = saved
    else
      ENV.delete("NO_COLOR")
    end
  end

  it "leaves Colorize alone when neither flag nor env is set" do
    saved_env = ENV["NO_COLOR"]?
    ENV.delete("NO_COLOR")
    Colorize.enabled = true

    Noir::CLI.apply_global_color_flag!(["list", "techs"])
    Colorize.enabled?.should be_true
  ensure
    Colorize.enabled = true
    if saved = saved_env
      ENV["NO_COLOR"] = saved
    else
      ENV.delete("NO_COLOR")
    end
  end
end
