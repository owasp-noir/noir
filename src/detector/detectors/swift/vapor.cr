require "../../../models/detector"

module Detector::Swift
  class Vapor < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check if this is a Package.swift file
      return false unless filename.includes?("Package.swift")

      # Look for vapor package dependency with more specific pattern
      # Matches patterns like: .package(url: "https://github.com/vapor/vapor.git", ...)
      check = file_contents.includes?("dependencies")
      check = check && (file_contents.includes?("vapor/vapor") ||
                        (file_contents.includes?("vapor") &&
                         file_contents.includes?(".package(")))

      check
    end

    def set_name
      @name = "swift_vapor"
    end
  end
end
