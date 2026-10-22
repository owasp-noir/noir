require "../../../models/detector"

module Detector::Javascript
  class FirebaseFunctions < Detector
    detector_for "js_firebase_functions", extensions: %w[.js .mjs .cjs .jsx .ts .tsx]

    # `firebase-functions`, `firebase-functions/v1`, `firebase-functions/v2/https`, ...
    SIGNAL = /(?:\bfrom\s*|\brequire\s*\(\s*)['"]firebase-functions(?:\/[^'"]*)?['"]/

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      return false unless file_contents.includes?("firebase-functions")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
