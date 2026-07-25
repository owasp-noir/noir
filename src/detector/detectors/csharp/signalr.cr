require "../../../models/detector"

module Detector::CSharp
  # Detects ASP.NET Core SignalR: the `Microsoft.AspNetCore.SignalR`
  # namespace (present in every hub/startup file) or a `MapHub<T>(...)`
  # mount. Gates the SignalR analyzer, which emits hub methods as `ws://`
  # realtime endpoints.
  class SignalR < Detector
    detector_for "cs_signalr", extensions: %w[.cs]

    SIGNALR_MARKER = /Microsoft\.AspNetCore\.SignalR\b|\bMapHub\s*</

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cs")
      content_matches?(file_contents, SIGNALR_MARKER)
    end
  end
end
