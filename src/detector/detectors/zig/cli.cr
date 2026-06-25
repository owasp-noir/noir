require "../../../models/detector"

module Detector::Zig
  # Detects Zig command-line apps via zig-cli, zig-clap, or std.process argv
  # parsing. Never gates on bare getEnvMap (zap/jetzig/httpz config).
  class Cli < Detector
    MARKERS = /@import\s*\(\s*"cli"\s*\)|@import\s*\(\s*"clap"\s*\)|\b(?:std\.)?process\.argsAlloc\s*\(|\bclap\.(?:parseParamsComptime|parse)\b|\bcli\.(?:Command|App|Runner)\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".zig")
      file_contents.matches?(MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".zig")
    end

    def set_name
      @name = "zig_cli"
    end
  end
end
