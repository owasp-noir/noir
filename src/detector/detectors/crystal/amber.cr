require "../../../models/detector"

module Detector::Crystal
  class Amber < Detector
    detector_for "crystal_amber", extensions: %w[.cr], basenames: %w[shard.yml shard.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("amberframework/amber")
    end
  end
end
