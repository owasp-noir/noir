require "../../../models/detector"

module Detector::Zig
  # Detects Zig command-line apps via zig-cli, zig-clap, zig-args, yazap, or
  # std.process argv parsing. Never gates on bare getEnvMap (zap/jetzig/httpz
  # config).
  class Cli < Detector
    detector_for "zig_cli", extensions: %w[.zig]

    MARKERS = /@import\s*\(\s*"cli"\s*\)|@import\s*\(\s*"clap"\s*\)|@import\s*\(\s*"args"\s*\)|@import\s*\(\s*"yazap"\s*\)|\b(?:std\.)?process\.argsAlloc\s*\(|\bclap\.(?:parseParamsComptime|parse)\b|\bcli\.(?:Command|App|Runner)\b/

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".zig")
      content_matches?(file_contents, MARKERS)
    end
  end
end
