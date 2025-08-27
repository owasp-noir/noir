require "../../../models/detector"

module Detector::Crystal
  class Grip < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("grip-framework/grip")
      check = check && filename.includes?("shard.yml")

      check
    end

    def set_name
      @name = "crystal_grip"
    end
  end
end
