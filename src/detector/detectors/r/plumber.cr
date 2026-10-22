require "../../../models/detector"

module Detector::R
  class Plumber < Detector
    detector_for "r_plumber", extensions: %w[.R .r]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".R") || filename.ends_with?(".r")

      # plumber library import
      return true if content_matches?(file_contents, /library\s*\(\s*plumber\s*\)/)
      return true if content_matches?(file_contents, /require\s*\(\s*plumber\s*\)/)
      return true if file_contents.includes?("plumber::")

      # Plumber annotations
      return true if content_matches?(file_contents, /^\s*#\*\s*@(?:get|post|put|delete|patch|head|options|apiTitle|apiDescription|param|serializer)\b/mi)

      # Programmatic plumber routing functions
      return true if content_matches?(file_contents, /\bpr_(?:get|post|put|delete|patch|head|options|handle|mount)\b/i)

      false
    end
  end
end
