require "../../../models/detector"

module Detector::Zig
  class Zap < Detector
    def detect(filename : String, file_contents : String) : Bool
      return true if filename.ends_with?(".zig") && file_contents.includes?("@import(\"zap\")")

      if File.basename(filename) == "build.zig.zon"
        return true if content_matches?(file_contents, /\.zap\s*=\s*\.\{/)
        return true if file_contents.includes?("zigzap/zap")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".zig") || File.basename(filename) == "build.zig.zon"
    end

    def set_name
      @name = "zig_zap"
    end
  end
end
