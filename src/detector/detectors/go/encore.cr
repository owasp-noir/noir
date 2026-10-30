require "../../../models/detector"

module Detector::Go
  class Encore < Detector
    detector_for "go_encore", extensions: %w[.go], path_segments: %w[go.mod]

    # `require encore.dev vX` in go.mod, an `encore.dev/...` import, or a
    # `//encore:api` directive.
    SIGNAL = Regex.union(/\bencore\.dev\s+v\d/, /"encore\.dev\//, /^\/\/encore:api\b/m)

    def detect(filename : String, file_contents : String) : Bool
      go_mod_dependency?(filename, file_contents, SIGNAL) ||
        (filename.ends_with?(".go") && content_matches?(file_contents, SIGNAL))
    end
  end
end
