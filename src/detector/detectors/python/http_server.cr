require "../../../models/detector"

module Detector::Python
  class HttpServer < Detector
    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".py")

      # Match stdlib http.server usage (import, from-import, or direct class/server tokens).
      # wsgiref.simple_server is related (per issue) but we intentionally do not auto-detect on it alone
      # here to avoid polluting :techs counts in framework fixtures that use wsgiref only as a test server
      # (e.g. pyramid fixture). Users can still force via similar names or future wsgi analyzer.
      return true if file_contents.includes?("http.server")
      return true if file_contents.includes?("BaseHTTPRequestHandler")
      return true if file_contents.includes?("SimpleHTTPRequestHandler")
      return true if file_contents.includes?("HTTPServer")

      false
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".py")
    end

    def set_name
      @name = "python_http_server"
    end
  end
end
