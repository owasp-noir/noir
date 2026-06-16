require "../../../models/detector"

module Detector::Crystal
  class Http < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cr")
      file_contents.includes?("http/server") || file_contents.includes?("HTTP::Server")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cr") || File.basename(filename) == "shard.yml" || File.basename(filename) == "shard.lock"
    end

    def set_name
      @name = "crystal_http"
    end
  end
end
