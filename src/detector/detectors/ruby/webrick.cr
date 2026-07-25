require "../../../models/detector"

module Detector::Ruby
  class Webrick < Detector
    MARKERS = Regex.union("WEBrick", "webrick", "mount_proc", "AbstractServlet")

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".rb") || filename.ends_with?(".ru")

      # WEBrick is Ruby stdlib (no gem required in modern Ruby). Detect on
      # source files only (applicable restricts to .rb/.ru) to avoid polluting
      # tech counts from incidental "webrick" mentions in Gemfiles of other
      # Ruby frameworks (e.g. rackup using webrick in a sinatra/rails Gemfile).
      # Mirrors python_http_server and crystal_http design.
      content_matches?(file_contents, MARKERS)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".rb") || filename.ends_with?(".ru")
    end

    def set_name
      @name = "ruby_webrick"
    end
  end
end
