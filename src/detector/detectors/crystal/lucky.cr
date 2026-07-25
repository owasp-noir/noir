require "../../../models/detector"

module Detector::Crystal
  class Lucky < Detector
    detector_for "crystal_lucky", extensions: %w[.cr], basenames: %w[shard.yml shard.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("luckyframework/lucky")
    end
  end
end
