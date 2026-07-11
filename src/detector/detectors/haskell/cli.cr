require "../../../models/detector"

module Detector::Haskell
  # Detects Haskell command-line apps via optparse-applicative, cmdargs,
  # System.Console.GetOpt, System.Environment.getArgs, or turtle's
  # Turtle.Options. Never gates on bare getEnv/lookupEnv (Scotty/Servant
  # config).
  class Cli < Detector
    # Turtle re-exports Turtle.Options from the top-level Turtle module,
    # which is used pervasively for plain shell scripting too, so gate on
    # either the qualified submodule import or an explicit `options` name
    # in the unqualified import list, never a bare `import Turtle`.
    TURTLE_MARKERS = /\bimport\s+(?:qualified\s+)?Turtle\.Options\b|\bimport\s+(?:qualified\s+)?Turtle\b\s*\([^)]*\boptions\b[^)]*\)/

    MARKERS = /\bimport\s+(?:qualified\s+)?Options\.Applicative\b|\b(?:execParser|customExecParser|strOption|subparser|hsubparser)\b|\bimport\s+(?:qualified\s+)?System\.Console\.(?:GetOpt|CmdArgs)\b|\bimport\s+(?:qualified\s+)?System\.Environment\b|#{TURTLE_MARKERS}/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".hs") || filename.ends_with?(".lhs")
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".hs") || filename.ends_with?(".lhs")
    end

    def set_name
      @name = "haskell_cli"
    end
  end
end
