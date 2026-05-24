require "./common"

# Translates v0.x terminal flags into v1 subcommand invocations.
#
# In v0 these flags would parse, print something, and exit:
#   --list-techs            -> noir list techs
#   --list-taggers          -> noir list taggers
#   --build-info            -> noir version --verbose
#   --generate-completion S -> noir completion S
#   --help-all              -> noir help
#
# Non-terminal v0 flags (`-b`, `-P`, `--ai-context`, ...) stay in ARGV.
# The router sends them to the default `scan` subcommand, which parses
# them via its own OptionParser. That keeps `noir -b ./app -P` working
# exactly as it did in v0.
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

  # v0 deliver/probe flag tokens, translated to their v1 equivalents
  # before the scan OptionParser sees ARGV. Doing the swap here keeps
  # the LEGACY block out of `scan -h` (and out of tab-completion)
  # entirely — there's no shadow `parser.on` for each old flag name —
  # while existing CI scripts and v0 Dockerfile entrypoints keep
  # parsing without modification. Mirrors the YAML-side migration in
  # `ConfigInitializer::LEGACY_CONFIG_KEY_MAP`.
  LEGACY_FLAG_ALIASES = {
    "--send-req"     => "--probe",
    "--send-proxy"   => "--probe-via",
    "--send-es"      => "--export-es",
    "--with-headers" => "--probe-header",
    "--use-matchers" => "--probe-match",
    "--use-filters"  => "--probe-skip",
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
          Noir::CLI.die("--generate-completion requires a shell argument (zsh|bash|fish|elvish).")
        end
      end
    end
    argv
  end

  # Walks ARGV and rewrites any v0 deliver/probe flag token to its v1
  # equivalent. Handles both the bare form (`--send-proxy URL`) and
  # the `=` form (`--send-proxy=URL`) so neither shape leaks the v0
  # name into the OptionParser. Unknown tokens pass through
  # unchanged — this method intentionally narrow.
  def self.translate_flag_aliases(argv : Array(String)) : Array(String)
    argv.map do |arg|
      if eq_idx = arg.index('=')
        name = arg[0...eq_idx]
        if replacement = LEGACY_FLAG_ALIASES[name]?
          "#{replacement}#{arg[eq_idx..]}"
        else
          arg
        end
      else
        LEGACY_FLAG_ALIASES[arg]? || arg
      end
    end
  end
end
