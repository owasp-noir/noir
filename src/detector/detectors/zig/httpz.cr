require "../../../models/detector"

module Detector::Zig
  class Httpz < Detector
    def detect(filename : String, file_contents : String) : Bool
      return true if filename.ends_with?(".zig") && file_contents.includes?("@import(\"httpz\")")

      if File.basename(filename) == "build.zig.zon"
        return true if file_contents.matches?(/\.httpz\s*=\s*\.\{/)
        return true if file_contents.includes?("karlseguin/http.zig")
      end

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".zig") || File.basename(filename) == "build.zig.zon"
    end

    def set_name
      @name = "zig_httpz"
    end
  end
end
