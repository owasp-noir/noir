require "../../../models/detector"

module Detector::Crystal
  class Marten < Detector
    detector_for "crystal_marten", extensions: %w[.cr], basenames: %w[shard.yml shard.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes?("shard.yml")

      file_contents.includes?("martenframework/marten")
    end
  end
end
