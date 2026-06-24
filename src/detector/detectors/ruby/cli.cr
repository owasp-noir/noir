require "../../../models/detector"

module Detector::Ruby
  # Detects Ruby command-line applications: programs that parse argv via the
  # stdlib OptionParser, a `< Thor` subclass, or a CLI gem (gli, slop,
  # tty-option, commander), or that index ARGV directly. Gates the Ruby CLI
  # analyzer. Intentionally import/usage-anchored: bare `ENV[...]` or a plain
  # `ARGV` reference (without an index) is too common in web apps to qualify.
  class Cli < Detector
    CLI_GEMS = ["thor", "gli", "slop", "tty-option", "commander"]

    REQUIRE_OPTPARSE = /\brequire\s+["']optparse["']/
    OPTION_PARSER    = /\bOptionParser\.new\b/
    THOR_SUBCLASS    = /<\s*Thor\b/
    GLI_APP          = /\binclude\s+GLI::App\b/
    SLOP_USE         = /\bSlop\.(?:parse|new)\b/
    TTY_OPTION       = /\binclude\s+TTY::Option\b/
    COMMANDER_USE    = /\binclude\s+Commander::Methods\b/
    ARGV_INDEX       = /\bARGV\s*\[\s*\d+\s*\]/

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)
      if base == "Gemfile" || filename.ends_with?(".gemspec")
        return CLI_GEMS.any? { |gem| gemfile_dependency?(file_contents, gem) || gemspec_dependency?(file_contents, gem) }
      end

      return false unless filename.ends_with?(".rb")
      return true if file_contents.matches?(REQUIRE_OPTPARSE) || file_contents.matches?(OPTION_PARSER)
      return true if file_contents.matches?(THOR_SUBCLASS) || file_contents.includes?("require \"thor\"") || file_contents.includes?("require 'thor'")
      return true if file_contents.matches?(GLI_APP) || file_contents.matches?(SLOP_USE) ||
                     file_contents.matches?(TTY_OPTION) || file_contents.matches?(COMMANDER_USE)
      return true if file_contents.matches?(ARGV_INDEX)

      false
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
