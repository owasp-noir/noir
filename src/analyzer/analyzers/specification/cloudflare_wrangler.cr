require "../../engines/specification_engine"
require "toml"

module Analyzer::Specification
  class CloudflareWrangler < SpecificationEngine
    analyzer_for "cloudflare_wrangler"

    METHOD_ANY = "ANY"

    # A route pattern is `[scheme://]<host><path>` — `example.com/api/*`,
    # `*.example.com/*`, `https://example.com/api/*`.
    ROUTE_PATTERN_RE = /\A(?:[a-z][a-z0-9+.-]*:\/\/)?([^\/]+)(\/.*)?\z/i

    # Fallback for a `wrangler.toml` the TOML shard refuses. `pattern = "..."`
    # only ever appears inside a `routes` entry in a wrangler config, so it can
    # be scanned document-wide; the bare-string form has no such marker and is
    # recovered from inside the `routes = [ … ]` array only.
    TOML_PATTERN_RE      = /(?:^|[\s{,])pattern\s*=\s*"([^"]+)"/m
    TOML_ROUTES_ARRAY_RE = /^\s*routes\s*=\s*\[([^\]]*)\]/m
    TOML_INLINE_TABLE_RE = /\{[^}]*\}/
    TOML_STRING_RE       = /"([^"]+)"/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::CLOUDFLARE_WRANGLER_SPEC) do |path, details|
        content = read_file_content(path)
        if path.ends_with?(".toml")
          process_toml(content, details)
        else
          process_json(content, details)
        end
      end

      @result
    end

    private def process_toml(content : String, details : Details)
      doc = begin
        TOML.parse(content)
      rescue e
        # The bundled TOML shard predates TOML 1.0 and rejects a mixed-type
        # array, which is exactly how wrangler documents `routes`:
        # `routes = ["example.com/*", { pattern = "...", zone_name = "..." }]`.
        # One such array used to cost every route in the file, so fall back to
        # scanning the `pattern` assignments rather than dropping the config.
        logger.debug "Cloudflare wrangler TOML parse failed, falling back to pattern scan: #{e}"
        process_toml_fallback(content, details)
        return
      end

      routes = doc["routes"]?
      return unless routes
      arr = routes.as_a?
      return unless arr
      arr.each { |entry| emit_toml_route(entry, details) }
    end

    private def process_toml_fallback(content : String, details : Details)
      content.scan(TOML_PATTERN_RE) { |m| register_endpoint(m[1], nil, details) }

      content.scan(TOML_ROUTES_ARRAY_RE) do |m|
        # Inline tables were already covered by the `pattern =` scan above;
        # dropping them here leaves only the bare-string route entries.
        m[1].gsub(TOML_INLINE_TABLE_RE, "").scan(TOML_STRING_RE) do |s|
          register_endpoint(s[1], nil, details)
        end
      end
    end

    private def process_json(content : String, details : Details)
      # `wrangler.jsonc` allows comments; strip them before parsing.
      doc = JSON.parse(strip_jsonc_comments(content))
      routes = doc["routes"]?
      return unless routes
      arr = routes.as_a?
      return unless arr
      arr.each { |entry| emit_json_route(entry, details) }
    end

    private def emit_toml_route(entry : TOML::Any, details : Details)
      pattern = nil
      zone = nil

      if h = entry.as_h?
        pattern = h["pattern"]?.try(&.as_s?)
        zone = h["zone_name"]?.try(&.as_s?) || h["zone_id"]?.try(&.as_s?)
      elsif s = entry.as_s?
        pattern = s
      end

      register_endpoint(pattern, zone, details)
    end

    private def emit_json_route(entry : JSON::Any, details : Details)
      pattern = nil
      zone = nil

      if h = entry.as_h?
        pattern = h["pattern"]?.try(&.as_s?)
        zone = h["zone_name"]?.try(&.as_s?) || h["zone_id"]?.try(&.as_s?)
      elsif s = entry.as_s?
        pattern = s
      end

      register_endpoint(pattern, zone, details)
    end

    private def register_endpoint(pattern : String?, zone : String?, details : Details)
      return if pattern.nil? || pattern.empty?

      host, path = split_route_pattern(pattern)

      endpoint = Endpoint.new(path, METHOD_ANY, details)
      endpoint.add_tag(Tag.new("wrangler-scope", "route", "cloudflare_wrangler_analyzer"))
      endpoint.add_tag(Tag.new("wrangler-host", host, "cloudflare_wrangler_analyzer")) if host && !host.empty?
      endpoint.add_tag(Tag.new("wrangler-zone", zone, "cloudflare_wrangler_analyzer")) if zone && !zone.empty?
      @result << endpoint
    end

    # A wrangler route pattern is host-qualified: `example.com/api/*`. The host
    # is routing context, not part of the request path, so keeping it inline
    # produced URLs like `/example.com/api/*` — a path no request ever carries.
    # Split it out and keep it as a tag.
    private def split_route_pattern(pattern : String) : Tuple(String?, String)
      trimmed = pattern.strip
      return {nil, trimmed} if trimmed.starts_with?('/')

      if m = ROUTE_PATTERN_RE.match(trimmed)
        path = m[2]? || "/"
        return {m[1], path}
      end

      {nil, trimmed}
    end

    private def strip_jsonc_comments(content : String) : String
      result = String.build do |io|
        in_string = false
        escape = false
        i = 0
        chars = content.chars
        while i < chars.size
          c = chars[i]
          if in_string
            io << c
            if escape
              escape = false
            elsif c == '\\'
              escape = true
            elsif c == '"'
              in_string = false
            end
            i += 1
            next
          end

          if c == '"'
            in_string = true
            io << c
            i += 1
          elsif c == '/' && i + 1 < chars.size && chars[i + 1] == '/'
            # line comment: skip to end of line
            while i < chars.size && chars[i] != '\n'
              i += 1
            end
          elsif c == '/' && i + 1 < chars.size && chars[i + 1] == '*'
            # block comment: skip until */
            i += 2
            while i + 1 < chars.size && !(chars[i] == '*' && chars[i + 1] == '/')
              i += 1
            end
            i += 2
          else
            io << c
            i += 1
          end
        end
      end
      result
    end
  end
end
