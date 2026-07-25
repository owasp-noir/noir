require "../../../models/detector"

module Detector::Zig
  class Zap < Detector
    detector_for "zig_zap", extensions: %w[.zig], basenames: %w[build.zig.zon]

    def detect(filename : String, file_contents : String) : Bool
      return true if filename.ends_with?(".zig") && file_contents.includes?("@import(\"zap\")")

      if File.basename(filename) == "build.zig.zon"
        return true if content_matches?(file_contents, /\.zap\s*=\s*\.\{/)
        return true if file_contents.includes?("zigzap/zap")
      end

      false
    end
  end
end
