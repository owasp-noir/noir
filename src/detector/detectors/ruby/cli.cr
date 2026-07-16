require "../../../models/detector"

module Detector::Ruby
  # Detects Ruby command-line applications: programs that parse argv via the
  # stdlib OptionParser, a `< Thor` subclass, or a CLI gem (gli, slop,
  # tty-option, commander, optimist, clamp, dry-cli), or that index ARGV
  # directly. Gates the Ruby CLI analyzer. Intentionally import/usage-anchored:
  # bare `ENV[...]` or a plain `ARGV` reference (without an index) is too
  # common in web apps to qualify.
  class Cli < Detector
    CLI_GEMS = ["thor", "gli", "slop", "tty-option", "commander", "optimist", "clamp", "dry-cli"]

    REQUIRE_OPTPARSE = /\brequire\s+["']optparse["']/
    OPTION_PARSER    = /\bOptionParser\.new\b/
    THOR_SUBCLASS    = /<\s*Thor\b/
    GLI_APP          = /\binclude\s+GLI::App\b/
    SLOP_USE         = /\bSlop\.(?:parse|new)\b/
    TTY_OPTION       = /\binclude\s+TTY::Option\b/
    COMMANDER_USE    = /\binclude\s+Commander::Methods\b/
    ARGV_INDEX       = /\bARGV\s*\[\s*\d+\s*\]/
    OPTIMIST_USE     = /\bOptimist(?:::|\.)options\b/
    CLAMP_SUBCLASS   = /<\s*Clamp::Command\b/
    DRY_CLI_SUBCLASS = /<\s*Dry::CLI::Command\b/

    # Single-pass union of every source marker above (the two thor require
    # forms were bare `includes?` probes; `Regex.union` escapes string
    # arguments literally). The previous chain scanned the whole file up to
    # 11 times on non-CLI Ruby sources — the common case.
    CLI_MARKER = Regex.union(
      REQUIRE_OPTPARSE, OPTION_PARSER, THOR_SUBCLASS,
      "require \"thor\"", "require 'thor'",
      GLI_APP, SLOP_USE, TTY_OPTION, COMMANDER_USE, ARGV_INDEX,
      OPTIMIST_USE, CLAMP_SUBCLASS, DRY_CLI_SUBCLASS,
    )

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)
      if base == "Gemfile" || filename.ends_with?(".gemspec")
        return CLI_GEMS.any? { |gem| gemfile_dependency?(file_contents, gem) || gemspec_dependency?(file_contents, gem) }
      end

      return false unless filename.ends_with?(".rb")
      file_contents.matches?(CLI_MARKER)
    end

    def applicable?(filename : String) : Bool
      base = File.basename(filename)
      filename.ends_with?(".rb") || filename.ends_with?(".gemspec") || base == "Gemfile"
    end

    def set_name
      @name = "ruby_cli"
    end
  end
end
