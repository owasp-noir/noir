require "../../../models/detector"

module Detector::Swift
  class Vapor < Detector
    def detect(filename : String, file_contents : String) : Bool
      # Check if this is a Package.swift file
      return false unless filename.includes?("Package.swift")

      # Require the Vapor framework itself, not just any package from the
      # `vapor/*` org. Hummingbird apps routinely pull `vapor/fluent-kit`,
      # `vapor/fluent-sqlite-driver`, `vapor/jwt-kit`, etc. — matching a
      # bare "vapor" substring there falsely tagged those projects as Vapor
      # and produced phantom endpoints from the Vapor analyzer.
      return false unless file_contents.includes?("dependencies")

      file_contents.includes?("vapor/vapor") ||
        file_contents.includes?(%(package: "vapor")) ||
        file_contents.includes?(%(name: "Vapor"))
    end

    def applicable?(filename : String) : Bool
      File.basename(filename) == "Package.swift"
    end

    def set_name
      @name = "swift_vapor"
    end
  end
end
