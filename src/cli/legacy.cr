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
  # Global short-circuits for *v0-shaped* invocations. v0 had no verb,
  # so these flags could sit anywhere in ARGV; the first one found
  # rewrites the whole invocation to the canonical v1 subcommand call.
  # A v1 invocation that opens with a verb is exempt — see `rewrite`.
  TERMINAL_REWRITES = {
    "--list-techs"   => ["list", "techs"],
    "--list-taggers" => ["list", "taggers"],
    "--build-info"   => ["version", "--verbose"],
    "--help-all"     => ["help"],
    "-v"             => ["version"],
    "-V"             => ["version"],
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

  # True when ARGV opens with a v1 verb, i.e. exactly the shape the
  # router dispatches to a subcommand (`head` must be in
  # `KNOWN_COMMANDS`). Everything after that verb is that subcommand's
  # own argv and must reach its own parser untouched.
  #
  # Leading global flags are skipped for the same reason the router skips
  # them: `noir --no-color rules update -v` is a v1 subcommand invocation,
  # and testing `argv.first` alone let the `-v => version` rewrite hijack
  # `rules update`'s own `-v` — printing the version and exiting 0 while
  # the rules were never updated.
  def self.subcommand_invocation?(argv : Array(String)) : Bool
    head = argv[Noir::CLI.verb_index(argv)]?
    return false if head.nil?
    Noir::CLI::KNOWN_COMMANDS.includes?(head)
  end

  # Returns a possibly-rewritten ARGV. If a terminal v0 flag is found,
  # the entire ARGV is replaced with the equivalent v1 invocation.
  #
  # The scan stops before it starts on a v1 subcommand invocation. The
  # rewrite table is a *global* argv substitution, so scanning past a
  # verb let it hijack that subcommand's own flags: `noir rules update
  # -v` matched `-v => ["version"]`, printed the version and exited 0
  # while `noir rules --help` advertises `-v, --verbose` and the rules
  # were never updated — silently turning the documented
  # `noir rules update && noir scan . -P` precondition into a no-op that
  # reports success. `-V`, `--version`, `--list-techs`, `--build-info`,
  # `--help-all` and `--generate-completion` had the identical exposure,
  # so the rule itself is scoped rather than the one entry. v0
  # invocations are unaffected: they have no verb to open with (v0 had
  # no subcommands), so `noir -b ./app --list-techs` still rewrites.
  def self.rewrite(argv : Array(String)) : Array(String)
    return argv if subcommand_invocation?(argv)

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
