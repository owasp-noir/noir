require "../../../models/detector"

module Detector::Javascript
  class Express < Detector
    # No `basenames: %w[package.json]`: `"express": "^4.x"` in a manifest
    # is not evidence of a hand-written Express app, because Feathers,
    # Sails and NestJS all carry Express as a transitive dependency.
    # Detection stays source-only. The declaration used to be there and
    # was dead anyway — `detect` rejected every non-source filename — so
    # dropping it changes no result, it just stops handing `package.json`
    # to a `detect` that always answered false.
    detector_for "js_express",
      extensions: %w[.js .mjs .cjs .jsx .ts .tsx]

    # Single precompiled alternation — one PCRE2 scan over the file
    # instead of up to four separate `.match` passes. Regex.union wraps
    # each branch verbatim, so the boolean result is identical.
    SIGNAL = Regex.union(
      /require\(['"]express['"]\)/,
      /from ['"]express['"]/,
      /app\.use\(express\.json\(\)\)/,
      /app\.use\(express\.urlencoded\(\{ extended: true \}\)\)/,
    )

    # Mirrors the `extensions:` list above. The two drifted before: the
    # gate admitted `.jsx`/`.tsx`, this guard did not, so a project whose
    # only Express source was a `.jsx` file reported "No technologies
    # detected" while the analyzer was perfectly able to parse it.
    SOURCE_EXTENSIONS = %w[.js .mjs .cjs .jsx .ts .tsx]

    def detect(filename : String, file_contents : String) : Bool
      return false unless SOURCE_EXTENSIONS.any? { |ext| filename.ends_with?(ext) }
      content_matches?(file_contents, SIGNAL)
    end
  end
end
