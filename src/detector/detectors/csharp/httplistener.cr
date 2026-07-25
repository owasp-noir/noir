require "../../../models/detector"

module Detector::CSharp
  class HttpListener < Detector
    detector_for "cs_httplistener", extensions: %w[.cs]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cs")
      return false unless file_contents.includes?("HttpListener")

      content_matches?(file_contents, /\bnew\s+HttpListener\s*\(/) ||
        content_matches?(file_contents, /\bnew\s+System\.Net\.HttpListener\s*\(/) ||
        file_contents.includes?(".Prefixes.Add") ||
        file_contents.includes?(".GetContext") ||
        file_contents.includes?("GetContextAsync")
    end
  end
end
