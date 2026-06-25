require "../../../models/detector"

module Detector::Haskell
  # Detects Haskell command-line apps via optparse-applicative, cmdargs,
  # System.Console.GetOpt, or System.Environment.getArgs. Never gates on bare
  # getEnv/lookupEnv (Scotty/Servant config).
  class Cli < Detector
    MARKERS = /\bimport\s+(?:qualified\s+)?Options\.Applicative\b|\b(?:execParser|customExecParser|strOption|subparser|hsubparser)\b|\bimport\s+(?:qualified\s+)?System\.Console\.(?:GetOpt|CmdArgs)\b|\bimport\s+(?:qualified\s+)?System\.Environment\b/

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
