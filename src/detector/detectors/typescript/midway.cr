require "../../../models/detector"

module Detector::Typescript
  class Midway < Detector
    detector_for "ts_midway",
      extensions: %w[.ts],
      basenames: %w[package.json]

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "package.json"
        return file_contents.includes?("\"@midwayjs/core\"") || file_contents.includes?("\"@midwayjs/decorator\"")
      end

      filename.ends_with?(".ts") && content_matches?(file_contents, /(?:from\s*|require\(\s*)['"]@midwayjs\//)
    end
  end
end
