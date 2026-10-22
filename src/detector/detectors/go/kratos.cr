require "../../../models/detector"

module Detector::Go
  class Kratos < Detector
    detector_for "go_kratos", extensions: %w[.go], path_segments: %w[go.mod]

    # Kratos (https://go-kratos.dev/) versions its Go module path
    # (`v2`, `v3`, ...), so match the shared `go-kratos/kratos/v<N>`
    # prefix instead of pinning to a single major version. Any
    # sub-package import (transport/http, transport/grpc, log,
    # config, ...) is a valid signal that the project is Kratos-based.
    IMPORT_MARKER = /go-kratos\/kratos\/v\d+/

    def detect(filename : String, file_contents : String) : Bool
      if filename.includes?("go.mod") && content_matches?(file_contents, IMPORT_MARKER)
        return true
      end
      if filename.ends_with?(".go") && content_matches?(file_contents, IMPORT_MARKER)
        return true
      end
      false
    end
  end
end
