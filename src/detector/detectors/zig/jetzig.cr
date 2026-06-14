require "../../../models/detector"

module Detector::Zig
  class Jetzig < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Source files import the framework directly.
      return true if filename.ends_with?(".zig") && file_contents.includes?("@import(\"jetzig\")")

      # The Zig package manifest declares a `.jetzig` dependency. `.zon`
      # uses dot-prefixed field names, so match the dependency key.
      if File.basename(filename) == "build.zig.zon"
        return true if file_contents.matches?(/\.jetzig\s*=\s*\.\{/)
        return true if file_contents.includes?("jetzig-framework/jetzig")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".zig") || File.basename(filename) == "build.zig.zon"
    end

    def set_name
      @name = "zig_jetzig"
    end
  end
end
