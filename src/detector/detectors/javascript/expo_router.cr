require "../../../models/detector"

module Detector::Javascript
  # Expo Router is mostly client navigation; only its `+api` modules under
  # `app/` run on a server, so those files (not the `expo-router` package,
  # which every Expo app lists) mark an HTTP surface. The analyzer still
  # requires the closest package.json to name `expo-router`.
  class ExpoRouter < Detector
    detector_for "js_expo_router", extensions: %w[.js .jsx .ts .tsx]

    API_MODULE = /\+api\.[jt]sx?$/

    def detect(filename : String, file_contents : String) : Bool
      filename.matches?(API_MODULE) && base_relative_path(filename).includes?("/app/")
    end
  end
end
