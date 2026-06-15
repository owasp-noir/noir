require "../../../models/detector"

module Detector::Javascript
  # GraphQL Yoga is the second-most-used Node GraphQL server (The Guild
  # stack). It ships as `graphql-yoga`, plus scoped `@graphql-yoga/*`
  # plugins, and is increasingly common in Cloudflare Workers / edge
  # runtimes. The `createYoga` factory is the universal entry point, so
  # a literal-name match also covers wrapper helpers that re-export it.
  class GraphqlYoga < Detector
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
      file_contents.matches?(SIGNAL)
    end

    def applicable?(filename : String) : Bool
      filename.ends_with?(".js") || filename.ends_with?(".mjs") ||
        filename.ends_with?(".cjs") || filename.ends_with?(".jsx") ||
        filename.ends_with?(".ts") || filename.ends_with?(".tsx")
    end

    def set_name
      @name = "js_graphql_yoga"
    end
  end
end
