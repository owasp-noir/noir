require "../../../models/detector"

module Detector::Crystal
  class Marten < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("martenframework/marten")
    end

    def set_name
      @name = "crystal_marten"
    end
  end
end
