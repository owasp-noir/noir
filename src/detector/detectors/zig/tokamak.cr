require "../../../models/detector"

module Detector::Zig
  class Tokamak < Detector
    def detect(filename : String, file_contents : String) : Bool
      return true if filename.ends_with?(".zig") && file_contents.includes?("@import(\"tokamak\")")

      if File.basename(filename) == "build.zig.zon"
        return true if file_contents.matches?(/\.tokamak\s*=\s*\.\{/)
        return true if file_contents.includes?("cztomsik/tokamak")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".zig") || File.basename(filename) == "build.zig.zon"
    end

    def set_name
      @name = "zig_tokamak"
    end
  end
end
