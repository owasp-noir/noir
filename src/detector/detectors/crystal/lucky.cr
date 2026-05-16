require "../../../models/detector"

module Detector::Crystal
  class Lucky < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("luckyframework/lucky")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cr") || File.basename(filename) == "shard.yml" || File.basename(filename) == "shard.lock"
    end

    def set_name
      @name = "crystal_lucky"
    end
  end
end
