require "../../../models/detector"

module Detector::Zig
  class Tokamak < Detector
    detector_for "zig_tokamak", extensions: %w[.zig], basenames: %w[build.zig.zon]

    def detect(filename : String, file_contents : String) : Bool
      return true if filename.ends_with?(".zig") && file_contents.includes?("@import(\"tokamak\")")

      if File.basename(filename) == "build.zig.zon"
        return true if content_matches?(file_contents, /\.tokamak\s*=\s*\.\{/)
        return true if file_contents.includes?("cztomsik/tokamak")
      end

      false
    end
  end
end
