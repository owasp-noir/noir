require "../../../models/detector"

module Detector::Swift
  class Kitura < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check if this is a Package.swift file
      return false unless filename.includes?("Package.swift")

      # Look for Kitura package dependency
      # Matches patterns like: .package(url: "https://github.com/Kitura/Kitura.git", ...)
      check = file_contents.includes?("dependencies")
      check = check && (file_contents.includes?("Kitura/Kitura") ||
                        (file_contents.includes?("Kitura") &&
                         file_contents.includes?(".package(")))

      check
    end

    def set_name
      @name = "swift_kitura"
    end
  end
end
