require "../../../models/detector"

module Detector::Swift
  class Vapor < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("vapor")
      check = check && file_contents.includes?("dependencies")
      check = check && filename.includes?("Package.swift")

      check
    end

    def set_name
      @name = "swift_vapor"
    end
  end
end
