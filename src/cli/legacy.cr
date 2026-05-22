require "./common"

# Translates v0.x terminal flags into v1 subcommand invocations.
#
# In v0 these flags would parse, print something, and exit:
#   --list-techs           → noir list techs
#   --list-taggers         → noir list taggers
#   --build-info           → noir version --verbose
#   --generate-completion S → noir completion S
#   --help-all             → noir help
#
# Non-terminal v0 flags (`-b`, `-P`, `--ai-context`, …) stay in ARGV; the
# router routes them to the default `scan` subcommand, which parses them
# via its own OptionParser. That keeps `noir -b ./app -P` byte-identical
# to v0 behavior.
module Noir::CLI::Legacy
  # Global short-circuits. The first time any of these appear anywhere
  # in ARGV the entire invocation is rewritten to the canonical v1
  # subcommand call, so flags that are inherently global (`-v`,
  # `--version`) behave the same no matter whether the user typed them
  # before, after, or in place of a verb.
  TERMINAL_REWRITES = {
    "--list-techs"   => ["list", "techs"],
    "--list-taggers" => ["list", "taggers"],
    "--build-info"   => ["version", "--verbose"],
    "--help-all"     => ["help"],
    "-v"             => ["version"],
    "--version"      => ["version"],
  }

  # Returns a possibly-rewritten ARGV. If a terminal v0 flag is found,
  # the entire ARGV is replaced with the equivalent v1 invocation.
  def self.rewrite(argv : Array(String)) : Array(String)
    argv.each_with_index do |arg, i|
      if rewrite = TERMINAL_REWRITES[arg]?
        return rewrite.dup
      end

      if arg == "--generate-completion"
        if i + 1 < argv.size
          return ["completion", argv[i + 1]]
        else
          Noir::CLI.die("--generate-completion requires a shell argument (zsh|bash|fish).")
        end
      end
    end
    argv
  end
end
