require "../../../models/detector"

module Detector::Php
  # Detects PHP command-line applications. SOURCE-anchored only (never
  # composer.json, where `symfony/console` is a transitive web dependency):
  # a Symfony Console command class / use, Laravel Zero, League CLImate,
  # Minicli, Laravel Artisan (`$signature`), Robo (`Robo\Tasks`), WP-CLI
  # (`WP_CLI::add_command` / `WP_CLI_Command`), or builtin getopt / $argv
  # indexing.
  class Cli < Detector
    USE_SF_CONSOLE    = /\buse\s+Symfony\\Component\\Console\b/
    SF_COMMAND        = /\bclass\s+\w+\s+extends\s+(?:\\?Symfony\\Component\\Console\\Command\\)?Command\b/
    AS_COMMAND        = /#\[\s*AsCommand\b/
    LARAVEL_ZERO      = /\buse\s+LaravelZero\\Framework\b/
    CLIMATE           = /\buse\s+League\\CLImate\\CLImate\b/
    MINICLI           = /\buse\s+Minicli\\(?:App|Command)\b/
    GETOPT            = /\bgetopt\s*\(/
    ARGV_INDEX        = /\$argv\s*\[/
    ARTISAN_SIGNATURE = /protected\s+(?:static\s+)?\$signature\s*=\s*['"]/
    ROBO_MARKER       = /Robo\\Tasks\b/
    WP_ADD_COMMAND    = /WP_CLI::add_command\s*\(/
    WP_COMMAND_CLASS  = /extends\s+WP_CLI_Command\b/

    # NOTE: deliberately kept as a sequential `||` chain. A single
    # `Regex.union` of these 12 patterns benchmarked 1.38× SLOWER on
    # non-matching PHP content — each pattern's distinctive literal keeps
    # PCRE2's fast scan, which the wide alternation defeats.
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".php")
      content_matches?(file_contents, USE_SF_CONSOLE) || content_matches?(file_contents, SF_COMMAND) ||
        content_matches?(file_contents, AS_COMMAND) || content_matches?(file_contents, LARAVEL_ZERO) ||
        content_matches?(file_contents, CLIMATE) || content_matches?(file_contents, MINICLI) ||
        content_matches?(file_contents, GETOPT) || content_matches?(file_contents, ARGV_INDEX) ||
        content_matches?(file_contents, ARTISAN_SIGNATURE) || content_matches?(file_contents, ROBO_MARKER) ||
        content_matches?(file_contents, WP_ADD_COMMAND) || content_matches?(file_contents, WP_COMMAND_CLASS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php")
    end

    def set_name
      @name = "php_cli"
    end
  end
end
