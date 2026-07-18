require "../../../models/detector"

module Detector::CSharp
  # Detects ASP.NET Core SignalR: the `Microsoft.AspNetCore.SignalR`
  # namespace (present in every hub/startup file) or a `MapHub<T>(...)`
  # mount. Gates the SignalR analyzer, which emits hub methods as `ws://`
  # realtime endpoints.
  class SignalR < Detector
    SIGNALR_MARKER = /Microsoft\.AspNetCore\.SignalR\b|\bMapHub\s*</

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".cs")
      file_contents.matches?(SIGNALR_MARKER)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".cs")
    end

    def set_name
      @name = "cs_signalr"
    end
  end
end
