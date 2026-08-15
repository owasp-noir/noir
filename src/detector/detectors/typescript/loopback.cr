require "../../../models/detector"

module Detector::Typescript
  class Loopback < Detector
    detector_for "ts_loopback",
      extensions: %w[.ts .tsx .cts .mts],
      basenames: %w[package.json]

    # Single precompiled alternation — one PCRE2 scan instead of four.
    #
    # `from '@loopback/rest'` (rather than `import.*from ['"]@loopback\/rest['"]`)
    # so a multi-line import block — the shape the `lb4` CLI scaffolder
    # actually emits —
    #   import {
    #     get,
    #     post,
    #   } from '@loopback/rest';
    # still matches: `.` never spans a newline in Crystal regex, but the
    # closing `from '<module>'` is always on a single line regardless of how
    # many names precede it.
    SIGNAL = Regex.union(
      /from\s*['"]@loopback\/rest['"]/,
      /from\s*['"]@loopback\/core['"]/,
      /require\(\s*['"]@loopback\/rest['"]\s*\)/,
      /require\(\s*['"]@loopback\/core['"]\s*\)/,
    )

    def detect(filename : String, file_contents : String) : Bool
      if File.basename(filename) == "package.json"
        return file_contents.includes?("\"@loopback/core\"") || file_contents.includes?("\"@loopback/rest\"")
      end

      return false unless filename.ends_with?(".ts") || filename.ends_with?(".tsx") ||
                          filename.ends_with?(".cts") || filename.ends_with?(".mts")

      content_matches?(file_contents, SIGNAL)
    end
  end
end
