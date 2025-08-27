require "../../../models/detector"

module Detector::Crystal
  class Marten < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = file_contents.includes?("martenframework/marten")
      check = check && filename.includes?("shard.yml")

      check
    end

    def set_name
      @name = "crystal_marten"
    end
  end
end
