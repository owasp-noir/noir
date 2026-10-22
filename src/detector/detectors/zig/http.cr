require "../../../models/detector"

module Detector::Zig
  class Http < Detector
    detector_for "zig_http", extensions: %w[.zig], basenames: %w[build.zig.zon]

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".zig")

      return true if file_contents.includes?("std.http.Server")

      has_std = file_contents.includes?("@import(\"std\")") || file_contents.includes?("std.http")
      has_server_flow = file_contents.includes?(".receiveHead(") && file_contents.includes?(".head.target")
      has_response = file_contents.includes?(".respond(")

      has_std && has_server_flow && has_response
    end
  end
end
