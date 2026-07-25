require "../../../models/detector"

module Detector::Javascript
  class Express < Detector
    detector_for "js_express",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx],
      basenames: %w[package.json]

    # Single precompiled alternation — one PCRE2 scan over the file
    # instead of up to four separate `.match` passes. Regex.union wraps
    # each branch verbatim, so the boolean result is identical.
    SIGNAL = Regex.union(
      /require\(['"]express['"]\)/,
      /from ['"]express['"]/,
      /app\.use\(express\.json\(\)\)/,
      /app\.use\(express\.urlencoded\(\{ extended: true \}\)\)/,
    )

    def detect(filename : String, file_contents : String) : Bool
      return false unless filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".ts") || filename.ends_with?(".cjs")
      content_matches?(file_contents, SIGNAL)
    end
  end
end
