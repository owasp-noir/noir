require "base64"
require "uri"
require "xml"
require "../../../models/analyzer"

module Analyzer::Specification
  # Parses Burp Suite sitemap XML exports (`Target → Site map → right-click →
  # Save items`). Each `<item>` holds an absolute URL, a base64-encoded raw
  # HTTP request, and the response — the request blob is the source of truth
  # for method, path, headers, and body.
  class Burp < Analyzer
    def analyze
      locator = CodeLocator.instance
      burp_files = locator.all("burp-sitemap")
      return @result unless burp_files.is_a?(Array(String))

      burp_files.each do |path|
        next unless File.exists?(path)
        begin
          content = File.read(path, encoding: "utf-8", invalid: :skip)
          process_file(content, path)
        rescue e
          @logger.debug "Failed to parse Burp sitemap #{path}: #{e.message}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_file(content : String, path : String)
      # `NONET` blocks the parser from fetching external entities over the
      # network. Crystal's default already skips external-entity *substitution*,
      # but layering NONET on top keeps a malicious sitemap from turning the
      # analyzer into an SSRF gadget even if a future option change enables
      # NOENT.
      doc = XML.parse(content, XML::ParserOptions::NONET)
      root = doc.root
      return unless root && root.name == "items"

      # (method, normalized_path) → Endpoint. Burp sitemaps frequently
      # contain many entries for the same URL with different query/body
      # shapes; the issue specifies one endpoint per unique pair, with
      # params unioned across the duplicates.
      seen = {} of Tuple(String, String) => Endpoint
      details = Details.new(PathInfo.new(path))

      root.children.each do |item|
        next unless item.element? && item.name == "item"
        process_item(item, details, seen)
      end

      seen.each_value { |endpoint| @result << endpoint }
    end

    private def process_item(item : XML::Node, details : Details, seen : Hash(Tuple(String, String), Endpoint))
      request_node = find_child(item, "request")
      return unless request_node

      raw = decode_request(request_node)
      return if raw.empty?

      parsed = parse_raw_request(raw)
      return unless parsed
      method, target, headers, body = parsed
      return if method.empty? || target.empty?

      # Restrict by @url when the user supplied one — keeps the behaviour
      # consistent with HAR. The Burp `<url>` element holds the absolute
      # URL, so match against that rather than reconstructing it.
      if !@url.empty?
        item_url = child_text(item, "url")
        return unless item_url.includes?(@url)
      end

      path_only, query = split_target(target)
      key = {method, path_only}
      endpoint = seen[key]?
      if endpoint.nil?
        endpoint = Endpoint.new(path_only, method, [] of Param, details)
        seen[key] = endpoint
      end

      merge_query_params(endpoint, query)
      merge_headers(endpoint, headers)
      merge_body(endpoint, headers, body)
    end

    # Burp emits `base64="true"` in the documented export path, but the
    # schema allows plain text — honour the attribute rather than guessing.
    private def decode_request(node : XML::Node) : String
      raw = node.content || ""
      return "" if raw.empty?
      if node["base64"]? == "true"
        begin
          return Base64.decode_string(raw)
        rescue
          return ""
        end
      end
      raw
    end

    # Returns {method, request_target, headers, body} or nil on malformed
    # input. Manual parser instead of `HTTP::Request.from_io` so quirky
    # exports (extra whitespace, HTTP/2 pseudo-mappings, unusual methods)
    # don't get rejected wholesale.
    private def parse_raw_request(raw : String) : Tuple(String, String, Array(Tuple(String, String)), String)?
      # Burp guarantees CRLF, but tolerate LF-only for hand-edited
      # fixtures. Capture which separator hit so we can offset past it
      # without re-slicing the buffer.
      separator = "\r\n\r\n"
      separator_index = raw.index(separator)
      if separator_index.nil?
        separator = "\n\n"
        separator_index = raw.index(separator)
      end
      header_section = separator_index ? raw[0, separator_index] : raw
      body = separator_index ? raw[(separator_index + separator.size)..] : ""

      lines = header_section.split(/\r?\n/)
      return if lines.empty?

      request_line = lines.shift
      parts = request_line.split(' ', 3)
      return if parts.size < 2
      method = parts[0].strip.upcase
      target = parts[1].strip

      headers = [] of Tuple(String, String)
      lines.each do |line|
        next if line.empty?
        idx = line.index(':')
        next unless idx
        name = line[0, idx].strip
        value = line[(idx + 1)..].strip
        headers << {name, value} unless name.empty?
      end

      {method, target, headers, body}
    end

    # Splits the request target into (path, query). Burp proxies often
    # capture absolute-form targets (`GET http://host/path HTTP/1.1`) when
    # the client routed through it as a forward proxy; collapse those to
    # their path component so the dedup key matches sibling relative-form
    # entries.
    private def split_target(target : String) : Tuple(String, String)
      normalized = target
      if normalized.starts_with?("http://") || normalized.starts_with?("https://")
        begin
          uri = URI.parse(normalized)
          path = uri.path
          query = uri.query
          normalized = path.empty? ? "/" : path
          normalized = "#{normalized}?#{query}" if query && !query.empty?
        rescue e
          logger.debug "Failed to parse Burp target URL '#{target}': #{e}"
        end
      end

      if idx = normalized.index('?')
        {normalized[0, idx], normalized[(idx + 1)..]}
      else
        {normalized, ""}
      end
    end

    private def merge_query_params(endpoint : Endpoint, query : String)
      return if query.empty?
      query.split('&').each do |pair|
        next if pair.empty?
        name, _, value = pair.partition('=')
        decoded_name = safe_unescape(name)
        next if decoded_name.empty?
        push_unique(endpoint, Param.new(decoded_name, safe_unescape(value), "query"))
      end
    end

    private def merge_headers(endpoint : Endpoint, headers : Array(Tuple(String, String)))
      headers.each do |(name, value)|
        case name.downcase
        when "cookie"
          merge_cookies(endpoint, value)
        when "content-length", "content-type", "host"
          # Skip transport-level headers — they're either derived
          # automatically or carry no parameter signal.
          next
        else
          push_unique(endpoint, Param.new(name, value, "header"))
        end
      end
    end

    private def merge_cookies(endpoint : Endpoint, value : String)
      value.split(';').each do |pair|
        trimmed = pair.strip
        next if trimmed.empty?
        name, _, val = trimmed.partition('=')
        next if name.empty?
        push_unique(endpoint, Param.new(name, val, "cookie"))
      end
    end

    private def merge_body(endpoint : Endpoint, headers : Array(Tuple(String, String)), body : String)
      return if body.empty?
      content_type = headers.find { |(n, _)| n.downcase == "content-type" }.try(&.[1]) || ""
      content_type_lower = content_type.downcase

      # Burp's raw export keeps the trailing CRLF the server actually saw;
      # for our purposes that's just noise on the last value, so trim it
      # before any per-format parsing.
      trimmed_body = body.rstrip("\r\n")

      if content_type_lower.includes?("application/json")
        parse_json_body(endpoint, trimmed_body)
      elsif content_type_lower.includes?("application/x-www-form-urlencoded")
        trimmed_body.split('&').each do |pair|
          next if pair.empty?
          name, _, value = pair.partition('=')
          decoded_name = safe_unescape(name)
          next if decoded_name.empty?
          push_unique(endpoint, Param.new(decoded_name, safe_unescape(value), "form"))
        end
      elsif content_type_lower.includes?("multipart/form-data")
        # Parameters live in each part's Content-Disposition `name=` attribute.
        trimmed_body.scan(/name="([^"]+)"/) do |match|
          name = match[1]
          push_unique(endpoint, Param.new(name, "", "form"))
        end
      end
    end

    private def parse_json_body(endpoint : Endpoint, body : String)
      return if body.strip.empty?
      begin
        parsed = JSON.parse(body)
        if hash = parsed.as_h?
          hash.each_key do |key|
            push_unique(endpoint, Param.new(key, "", "json"))
          end
        end
      rescue e
        logger.debug "Failed to parse Burp JSON body for #{endpoint.url}: #{e}"
      end
    end

    private def push_unique(endpoint : Endpoint, param : Param)
      return if endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      endpoint.push_param(param)
    end

    private def safe_unescape(value : String) : String
      return value if value.empty?
      begin
        URI.decode_www_form(value)
      rescue
        value
      end
    end

    private def find_child(node : XML::Node, name : String) : XML::Node?
      node.children.each do |child|
        return child if child.element? && child.name == name
      end
      nil
    end

    private def child_text(node : XML::Node, name : String) : String
      child = find_child(node, name)
      child ? (child.content || "") : ""
    end
  end
end
