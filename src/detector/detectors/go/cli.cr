require "../../../models/detector"

module Detector::Go
  # Detects Go command-line applications: programs that parse argv / flags
  # through the stdlib `flag` package or a CLI framework (cobra, urfave/cli,
  # go-arg, go-flags, pflag), or that index `os.Args` directly. Gates the Go
  # CLI analyzer, which surfaces the argv / flag / env attack surface as
  # `cli://` endpoints.
  class Cli < Detector
    # CLI framework import paths. Presence of any of these — in go.mod or a
    # source import block — is a strong, unambiguous CLI signal.
    CLI_LIBRARY_MARKERS = [
      "github.com/spf13/cobra",
      "github.com/urfave/cli",
      "github.com/alexflint/go-arg",
      "github.com/jessevdk/go-flags",
      "github.com/spf13/pflag",
    ]

    # A real call into the stdlib `flag` package (not just the bare token
    # "flag", which appears in unrelated identifiers/comments).
    BUILTIN_FLAG_USE = /\bflag\.(?:Parse|Args?|NArg|String(?:Var)?|Int(?:64)?(?:Var)?|Uint(?:64)?(?:Var)?|Bool(?:Var)?|Float64(?:Var)?|Duration(?:Var)?|Var)\s*\(/

    # Direct argv indexing, e.g. `os.Args[1]`.
    ARGV_INDEX = /\bos\.Args\s*\[/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".go") || File.basename(filename) == "go.mod"
      return true if CLI_LIBRARY_MARKERS.any? { |marker| file_contents.includes?(marker) }

      # go.mod has no flag/argv usage of its own; only the library markers
      # above qualify it.
      return false unless filename.ends_with?(".go")
      return true if file_contents.includes?("\"flag\"") && file_contents.matches?(BUILTIN_FLAG_USE)
      return true if file_contents.matches?(ARGV_INDEX)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".go") || File.basename(filename) == "go.mod"
    end

    def set_name
      @name = "go_cli"
    end
  end
end
