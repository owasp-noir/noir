require "../../../models/detector"

module Detector::Crystal
  class Http < Detector
    detector_for "crystal_http", extensions: %w[.cr], basenames: %w[shard.yml shard.lock]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cr")
      file_contents.includes?("http/server") || file_contents.includes?("HTTP::Server")
    end
  end
end
