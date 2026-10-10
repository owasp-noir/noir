require "../../engines/javascript_engine"
require "../../../miniparsers/js_object_config_extractor"

module Analyzer::Javascript
  # Convex HTTP actions: `convex/http.ts` builds an `httpRouter()` and
  # registers routes on it as object literals, served on
  # `https://<deployment>.convex.site`:
  #
  #   http.route({ path: "/postMessage", method: "POST", handler })
  #   http.route({ pathPrefix: "/files/", method: "GET", handler })  → /files/*
  #
  # Queries and mutations (the client RPC surface) are not read.
  class Convex < JavascriptEngine
    analyzer_for "js_convex"

    PACKAGE_MARKERS = ["\"convex\":"]
    ROUTER_IMPORT   = /\bhttpRouter\b[^;]*?\bfrom\s*['"]convex\/server['"]|\brequire\s*\(\s*['"]convex\/server['"]\s*\)/
    METHODS         = ["GET", "POST", "PUT", "DELETE", "PATCH", "OPTIONS"]

    def analyze
      owners = js_package_owners(PACKAGE_MARKERS)
      return @result unless owners.values.includes?(true)

      ordered_scan_files(get_files_by_extensions(DEFAULT_EXTENSIONS)) do |path|
        content = read_file_content(path)
        next unless content.includes?("convex/server") && content.matches?(ROUTER_IMPORT)
        next unless owned_by_js_package?(path, owners)

        Noir::JSObjectConfigExtractor.extract(content, ["method", "handler"]).compact_map do |route|
          method = route.string("method").try(&.upcase)
          next unless method && METHODS.includes?(method)
          url = route.string("path") || route.string("pathPrefix").try { |prefix| "#{prefix}*" }
          next unless url && url.starts_with?('/')
          Endpoint.new(url, method, Details.new(PathInfo.new(path, route.line)))
        end
      end.each { |endpoints| @result.concat(endpoints) }
      @result
    end
  end
end
