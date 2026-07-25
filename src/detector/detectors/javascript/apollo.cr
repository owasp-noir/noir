require "../../../models/detector"

module Detector::Javascript
  class Apollo < Detector
    detector_for "js_apollo", extensions: %w[.js .mjs .cjs .jsx .ts .tsx]

    # Apollo Server v4 ships as `@apollo/server`; legacy v2/v3 use the
    # `apollo-server` / `apollo-server-*` family. `ApolloServer` shows up
    # in both, so a literal-name match catches plain `import { ApolloServer }`
    # too even when the scoped import is split across lines.
    SIGNALS = [
      /from\s+['"]@apollo\/server(?:\/[^'"]*)?['"]/,
      /require\(['"]@apollo\/server(?:\/[^'"]*)?['"]\)/,
      /from\s+['"]apollo-server(?:-[a-z]+)?['"]/,
      /require\(['"]apollo-server(?:-[a-z]+)?['"]\)/,
      /\bnew\s+ApolloServer\s*\(/,
    ]

    # Single precompiled alternation of SIGNALS — one PCRE2 scan instead
    # of one per signal.
    SIGNAL = Regex.union(SIGNALS)

    def detect(filename : String, file_contents : String) : Bool
      return false unless applicable?(filename)
      content_matches?(file_contents, SIGNAL)
    end
  end
end
