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

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".php")
      file_contents.matches?(USE_SF_CONSOLE) || file_contents.matches?(SF_COMMAND) ||
        file_contents.matches?(AS_COMMAND) || file_contents.matches?(LARAVEL_ZERO) ||
        file_contents.matches?(CLIMATE) || file_contents.matches?(MINICLI) ||
        file_contents.matches?(GETOPT) || file_contents.matches?(ARGV_INDEX) ||
        file_contents.matches?(ARTISAN_SIGNATURE) || file_contents.matches?(ROBO_MARKER) ||
        file_contents.matches?(WP_ADD_COMMAND) || file_contents.matches?(WP_COMMAND_CLASS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".php")
    end

    def set_name
      @name = "php_cli"
    end
  end
end
