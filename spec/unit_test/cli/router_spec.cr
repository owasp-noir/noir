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

  it "consumes only the immediate arg after --generate-completion" do
    # Anything past the shell name is irrelevant — the rewritten form
    # is a closed pair, so a trailing positional must be dropped
    # rather than smuggled through to the eventual scan call.
    Noir::CLI::Legacy.rewrite(["--generate-completion", "bash", "./extra"]).should eq(["completion", "bash"])
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

  it "honors the first terminal flag when several are present" do
    # Iteration order in `rewrite` is left-to-right, so the leftmost
    # terminal match wins. Lock that in so future refactors don't
    # silently change which subcommand `noir --list-techs --build-info`
    # routes to.
    Noir::CLI::Legacy.rewrite(["--list-techs", "--build-info"]).should eq(["list", "techs"])
    Noir::CLI::Legacy.rewrite(["--build-info", "--list-techs"]).should eq(["version", "--verbose"])
  end

  it "is idempotent on already-rewritten input" do
    # `rewrite` consumes the original v0 form and emits the v1 form,
    # which contains no terminal flags by construction — passing it
    # back in must not alter it.
    rewritten = Noir::CLI::Legacy.rewrite(["--list-techs"])
    Noir::CLI::Legacy.rewrite(rewritten).should eq(rewritten)
  end
end

describe "Noir::CLI::Legacy.translate_flag_aliases" do
  # The v0 deliver/probe flag tokens never reach the scan
  # OptionParser — they're rewritten here, so `scan -h` stays free
  # of a LEGACY section while old CI scripts keep parsing.
  it "translates --send-req to --probe" do
    Noir::CLI::Legacy.translate_flag_aliases(["--send-req"]).should eq(["--probe"])
  end

  it "translates value-bearing flags in the bare form" do
    Noir::CLI::Legacy.translate_flag_aliases([
      "--send-proxy", "http://localhost:8080",
    ]).should eq(["--probe-via", "http://localhost:8080"])
  end

  it "translates value-bearing flags in the = form" do
    Noir::CLI::Legacy.translate_flag_aliases([
      "--send-proxy=http://localhost:8080",
    ]).should eq(["--probe-via=http://localhost:8080"])
  end

  it "preserves a value containing `=` (e.g. URL with query string)" do
    Noir::CLI::Legacy.translate_flag_aliases([
      "--send-es=http://es:9200/_doc?id=42",
    ]).should eq(["--export-es=http://es:9200/_doc?id=42"])
  end

  it "translates every v0 deliver token together" do
    argv = [
      "--send-req",
      "--send-proxy", "http://localhost:8080",
      "--send-es", "http://es:9200",
      "--with-headers", "X-T: 1",
      "--use-matchers", "/api",
      "--use-filters", "/admin",
    ]
    expected = [
      "--probe",
      "--probe-via", "http://localhost:8080",
      "--export-es", "http://es:9200",
      "--probe-header", "X-T: 1",
      "--probe-match", "/api",
      "--probe-skip", "/admin",
    ]
    Noir::CLI::Legacy.translate_flag_aliases(argv).should eq(expected)
  end

  it "leaves unknown tokens untouched" do
    argv = ["-b", "./app", "--probe", "-u", "http://x"]
    Noir::CLI::Legacy.translate_flag_aliases(argv).should eq(argv)
  end

  it "is idempotent on v1-only input" do
    argv = ["--probe", "--probe-via", "http://x", "--probe-header", "X: 1"]
    Noir::CLI::Legacy.translate_flag_aliases(argv).should eq(argv)
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

  it "treats an empty NO_COLOR value as not-set per the no-color.org spec" do
    # The spec at https://no-color.org/ requires implementations to
    # ignore an empty value — opting out of color should require an
    # actual non-empty, non-"0" value.
    saved_env = ENV["NO_COLOR"]?
    ENV["NO_COLOR"] = ""
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

describe "Noir::CLI.no_color_env?" do
  it "returns false when NO_COLOR is unset" do
    saved = ENV["NO_COLOR"]?
    ENV.delete("NO_COLOR")
    Noir::CLI.no_color_env?.should be_false
  ensure
    if v = saved
      ENV["NO_COLOR"] = v
    else
      ENV.delete("NO_COLOR")
    end
  end

  it "returns false for an empty NO_COLOR" do
    saved = ENV["NO_COLOR"]?
    ENV["NO_COLOR"] = ""
    Noir::CLI.no_color_env?.should be_false
  ensure
    if v = saved
      ENV["NO_COLOR"] = v
    else
      ENV.delete("NO_COLOR")
    end
  end

  it "returns false for NO_COLOR=0 (explicit opt-in to color)" do
    saved = ENV["NO_COLOR"]?
    ENV["NO_COLOR"] = "0"
    Noir::CLI.no_color_env?.should be_false
  ensure
    if v = saved
      ENV["NO_COLOR"] = v
    else
      ENV.delete("NO_COLOR")
    end
  end

  it "returns true for any other non-empty NO_COLOR value" do
    saved = ENV["NO_COLOR"]?
    ENV["NO_COLOR"] = "1"
    Noir::CLI.no_color_env?.should be_true
    ENV["NO_COLOR"] = "yes"
    Noir::CLI.no_color_env?.should be_true
    ENV["NO_COLOR"] = "anything"
    Noir::CLI.no_color_env?.should be_true
  ensure
    if v = saved
      ENV["NO_COLOR"] = v
    else
      ENV.delete("NO_COLOR")
    end
  end
end
