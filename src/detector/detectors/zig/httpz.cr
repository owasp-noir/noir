require "../../../models/detector"

module Detector::Zig
  class Httpz < Detector
    detector_for "zig_httpz", extensions: %w[.zig], basenames: %w[build.zig.zon]

    def detect(filename : String, file_contents : String) : Bool
      return true if filename.ends_with?(".zig") && file_contents.includes?("@import(\"httpz\")")

      if File.basename(filename) == "build.zig.zon"
        return true if content_matches?(file_contents, /\.httpz\s*=\s*\.\{/)
        return true if file_contents.includes?("karlseguin/http.zig")
      end

      false
    end
  end
end
