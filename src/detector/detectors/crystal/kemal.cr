require "../../../models/detector"

module Detector::Crystal
  class Kemal < Detector
    def detect(filename : String, file_contents : String) : Bool
      check = filename.includes?("shard.yml")
      check = check && file_contents.includes?("kemalcr/kemal")

      check
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cr") || File.basename(filename) == "shard.yml" || File.basename(filename) == "shard.lock"
    end

    def set_name
      @name = "crystal_kemal"
    end
  end
end
