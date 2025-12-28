require "../../../models/detector"

module Detector::Swift
  class Hummingbird < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check if this is a Package.swift file
      return false unless filename.includes?("Package.swift")

      # Look for Hummingbird package dependency
      # Matches patterns like: .package(url: "https://github.com/hummingbird-project/hummingbird.git", ...)
      check = file_contents.includes?("dependencies")
      check = check && (file_contents.includes?("hummingbird-project/hummingbird") ||
                        (file_contents.includes?("Hummingbird") &&
                         file_contents.includes?(".package(")))

      check
    end

    def set_name
      @name = "swift_hummingbird"
    end
  end
end
