require "../../../models/detector"

module Detector::Javascript
  # GraphQL Yoga is the second-most-used Node GraphQL server (The Guild
  # stack). It ships as `graphql-yoga`, plus scoped `@graphql-yoga/*`
  # plugins, and is increasingly common in Cloudflare Workers / edge
  # runtimes. The `createYoga` factory is the universal entry point, so
  # a literal-name match also covers wrapper helpers that re-export it.
  class GraphqlYoga < Detector
    detector_for "js_graphql_yoga", extensions: %w[.js .mjs .cjs .jsx .ts .tsx]

    SIGNALS = [
      /from\s+['"]graphql-yoga(?:\/[^'"]*)?['"]/,
      /require\(['"]graphql-yoga(?:\/[^'"]*)?['"]\)/,
      /from\s+['"]@graphql-yoga\/[^'"]+['"]/,
      /require\(['"]@graphql-yoga\/[^'"]+['"]\)/,
      /\bcreateYoga\s*\(/,
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
