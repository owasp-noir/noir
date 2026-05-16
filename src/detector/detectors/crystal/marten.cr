require "../../../models/detector"

module Detector::Crystal
  class Marten < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("martenframework/marten")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cr") || File.basename(filename) == "shard.yml" || File.basename(filename) == "shard.lock"
    end

    def set_name
      @name = "crystal_marten"
    end
  end
end
