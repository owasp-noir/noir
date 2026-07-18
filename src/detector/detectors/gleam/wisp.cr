require "../../../models/detector"

module Detector::Gleam
  class Wisp < Detector
    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if base == "gleam.toml" || base == "manifest.toml"
        return true if file_contents.matches?(/^\s*wisp\s*=/m)
        return true if file_contents.matches?(/name\s*=\s*"wisp"/)
      end

      return false unless filename.ends_with?(".gleam")

      return true if file_contents.matches?(/^\s*import\s+wisp(?:\/[a-z_]+)?(?:\s|\.|$)/m)
      return true if file_contents.includes?("wisp.path_segments")

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".gleam") ||
        File.basename(filename) == "gleam.toml" ||
        File.basename(filename) == "manifest.toml"
    end

    def set_name
      @name = "gleam_wisp"
    end
  end
end
