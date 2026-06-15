require "../../../models/detector"

module Detector::Javascript
  class Express < Detector
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
      file_contents.matches?(SIGNAL)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") || filename.ends_with?(".cjs") || filename.ends_with?(".jsx") || filename.ends_with?(".ts") || filename.ends_with?(".tsx") || File.basename(filename) == "package.json"
    end

    def set_name
      @name = "js_express"
    end
  end
end
