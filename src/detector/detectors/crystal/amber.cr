require "../../../models/detector"

module Detector::Crystal
  class Amber < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("amberframework/amber")
    end

    def set_name
      @name = "crystal_amber"
    end
  end
end
