require "../../../models/detector"

module Detector::Crystal
  class Amber < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("amberframework/amber")
      check = check && filename.includes?("shard.yml")

      check
    end

    def set_name
      @name = "crystal_amber"
    end
  end
end
