require "../../../models/detector"

module Detector::R
  class Plumber < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".R") || filename.ends_with?(".r")

      # plumber library import
      return true if file_contents.matches?(/library\s*\(\s*plumber\s*\)/)
      return true if file_contents.matches?(/require\s*\(\s*plumber\s*\)/)
      return true if file_contents.includes?("plumber::")

      # Plumber annotations
      return true if file_contents.matches?(/^\s*#\*\s*@(?:get|post|put|delete|patch|head|options|apiTitle|apiDescription|param|serializer)\b/mi)

      # Programmatic plumber routing functions
      return true if file_contents.matches?(/\bpr_(?:get|post|put|delete|patch|head|options|handle|mount)\b/i)

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".R") || filename.ends_with?(".r")
    end

    def set_name
      @name = "r_plumber"
    end
  end
end
