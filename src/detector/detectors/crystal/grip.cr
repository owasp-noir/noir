require "../../../models/detector"

module Detector::Crystal
  class Grip < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("grip-framework/grip")
    end

    def set_name
      @name = "crystal_grip"
    end
  end
end
