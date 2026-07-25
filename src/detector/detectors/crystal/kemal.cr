require "../../../models/detector"

module Detector::Crystal
  class Kemal < Detector
    detector_for "crystal_kemal", extensions: %w[.cr], basenames: %w[shard.yml shard.lock]

    def detect(filename : String, file_contents : String) : Bool
      check = filename.includes?("shard.yml")
      check = check && file_contents.includes?("kemalcr/kemal")

      check
    end
  end
end
