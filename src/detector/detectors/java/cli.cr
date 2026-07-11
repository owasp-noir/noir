require "../../../models/detector"

module Detector::Java
  # Detects Java command-line applications. Gated strictly on CLI-library
  # imports or unambiguous arg-parser constructs — NOT on bare
  # `main(String[] args)` / `System.getenv`, which every Java app (web
  # servers included) has.
  class Cli < Detector
    LIB_IMPORTS = [
      "picocli.",
      "org.kohsuke.args4j",
      "com.beust.jcommander",
      "org.apache.commons.cli",
      "com.github.rvesse.airline",
      "io.airlift.airline",
      "joptsimple.",
    ]

    # NOTE: deliberately no `new\s+OptionParser\s*\(` alternative here — jopt-simple's
    # `OptionParser` is a common, generic class name apps also give their own
    # options-parsing helpers (e.g. a video/report settings `OptionParser`). Genuine
    # jopt-simple usage always requires `import joptsimple.*` or a `joptsimple.`
    # fully-qualified reference, which LIB_IMPORTS already covers — adding a bare
    # class-name pattern here would mistag unrelated classes as `java_cli`.
    USAGE = /\bnew\s+Options\s*\(\s*\)|\bOption\.builder\s*\(|\bnew\s+JCommander\s*\(|\bJCommander\.newBuilder\s*\(|\bnew\s+CmdLineParser\s*\(|\bnew\s+CommandLine\s*\(/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".java")
      return true if LIB_IMPORTS.any? { |marker| file_contents.includes?(marker) }
      file_contents.matches?(USAGE)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".java")
    end

    def set_name
      @name = "java_cli"
    end
  end
end
