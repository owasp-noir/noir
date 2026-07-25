require "../../../models/detector"

module Detector::Gleam
  class Wisp < Detector
    detector_for "gleam_wisp", extensions: %w[.gleam], basenames: %w[gleam.toml manifest.toml]

    def detect(filename : String, file_contents : String) : Bool
      base = File.basename(filename)

      if base == "gleam.toml" || base == "manifest.toml"
        return true if content_matches?(file_contents, /^\s*wisp\s*=/m)
        return true if content_matches?(file_contents, /name\s*=\s*"wisp"/)
      end

      return false unless filename.ends_with?(".gleam")

      return true if content_matches?(file_contents, /^\s*import\s+wisp(?:\/[a-z_]+)?(?:\s|\.|$)/m)
      return true if file_contents.includes?("wisp.path_segments")

      false
    end
  end
end
