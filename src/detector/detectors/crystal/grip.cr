require "../../../models/detector"

module Detector::Crystal
  class Grip < Detector
    detector_for "crystal_grip", extensions: %w[.cr], basenames: %w[shard.yml shard.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("grip-framework/grip")
    end
  end
end
