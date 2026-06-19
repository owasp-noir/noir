require "../../../models/detector"

module Detector::CSharp
  class HttpListener < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cs")
      return false unless file_contents.includes?("HttpListener")

      file_contents.matches?(/\bnew\s+HttpListener\s*\(/) ||
        file_contents.matches?(/\bnew\s+System\.Net\.HttpListener\s*\(/) ||
        file_contents.includes?(".Prefixes.Add") ||
        file_contents.includes?(".GetContext") ||
        file_contents.includes?("GetContextAsync")
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cs")
    end

    def set_name
      @name = "cs_httplistener"
    end
  end
end
