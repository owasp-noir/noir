require "../../../models/detector"

module Detector::Go
  class Mux < Detector
    detector_for "go_mux", extensions: %w[.go], path_segments: %w[go.mod]

    # `github.com/minio/mux` is a maintained hard fork of gorilla/mux and
    # exposes the same routing API, so a project that depends only on the
    # fork is still a mux project.
    IMPORT_PATHS = %w[github.com/gorilla/mux github.com/minio/mux]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.includes? "go.mod"
      IMPORT_PATHS.any? { |path| file_contents.includes? path }
    end
  end
end
