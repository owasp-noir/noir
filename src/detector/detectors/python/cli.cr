require "../../../models/detector"

module Detector::Python
  # Detects Python command-line applications: programs that parse argv via
  # argparse / getopt or a CLI framework (click, typer, fire, docopt).
  # Gates the Python CLI analyzer, which surfaces the argv / option / env
  # attack surface as `cli://` endpoints.
  #
  # Detection is intentionally import-anchored. A bare `import sys`
  # (sys.argv) is far too common to treat as CLI evidence on its own, so it
  # is only honored inside the analyzer when paired with a `__main__` guard.
  class Cli < Detector
    CLI_IMPORT_RE = /(?:^|\n)\s*(?:import|from)\s+(?:argparse|click|typer|fire|docopt|getopt)\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")
      file_contents.matches?(CLI_IMPORT_RE)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".py")
    end

    def set_name
      @name = "python_cli"
    end
  end
end
