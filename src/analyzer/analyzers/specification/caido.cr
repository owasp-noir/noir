require "base64"
require "uri"
require "../../../models/analyzer"

module Analyzer::Specification
  class Caido < Analyzer
    def analyze
      locator = CodeLocator.instance
      caido_files = locator.all("caido-json")
      return @result unless caido_files.is_a?(Array(String))

      caido_files.each do |path|
        next unless File.exists?(path)
        details = Details.new(PathInfo.new(path))
        content = File.read(path, encoding: "utf-8", invalid: :skip)

        begin
          data = JSON.parse(content)
          entries = data.as_a?
          next unless entries

          seen = Set(String).new

          entries.each do |entry|
            begin
              process_entry(entry, details, seen)
            rescue e
              @logger.debug "Exception processing caido entry in #{path}"
              @logger.debug_sub e
            end
          end
        rescue e
          @logger.debug "Exception processing #{path}"
          @logger.debug_sub e
        end
      end

      @result
    end

    private def process_entry(entry : JSON::Any, details : Details, seen : Set(String))
      obj = entry.as_h?
      return unless obj

      method = obj["method"]?.try(&.as_s?).try(&.upcase) || "GET"
      path = obj["path"]?.try(&.as_s?) || ""
      return if path.empty?

      # Caido's `path` field already excludes the host/query string,
      # but some entries store the full request URI here. Normalize
      # both shapes through URI.parse, falling back to the raw value.
      normalized_path = begin
        uri = URI.parse(path)
        uri.path.empty? ? path : uri.path
      rescue
        path
      end

      # Defensive: Caido stores leading-slash paths, but normalize odd
      # entries (`api/users`, full URLs already handled above) so the
      # endpoint URL always starts with `/`.
      unless normalized_path.starts_with?("/")
        normalized_path = "/" + normalized_path
      end

      key = "#{method} #{normalized_path}"
      return if seen.includes?(key)
      seen << key

      params = [] of Param

      # Top-level `query` is a URL-encoded query string (`a=1&b=2`).
      if query_str = obj["query"]?.try(&.as_s?)
        parse_query_string(query_str).each do |name|
          params << Param.new(name, "", "query")
        end
      end

      # `raw` carries the full base64-encoded HTTP request message.
      # We pull headers and (for form/JSON bodies) body keys from it.
      # Host/port/is_tls are intentionally dropped — Noir merges into
      # a `(method, path)` namespace, matching how HAR/Insomnia exports
      # are consumed downstream. Multi-host Caido exports therefore
      # collapse to per-path endpoints by design.
      if raw_value = obj["raw"]?.try(&.as_s?)
        unless raw_value.empty?
          extract_from_raw(raw_value, params)
        end
      end

      @result << Endpoint.new(normalized_path, method, params, details)
    end

    private def parse_query_string(query : String) : Array(String)
      names = [] of String
      return names if query.empty?
      query.lstrip('?').split('&').each do |pair|
        next if pair.empty?
        name = pair.split('=', 2).first
        names << name unless name.empty?
      end
      names
    end

    # Splits an HTTP/1.x request message (CRLF or LF terminated) into
    # headers and body, then extracts header params and body params
    # for known content types. Decoded as bytes first so a binary body
    # (image upload, protobuf, etc.) doesn't blow up UTF-8 validation
    # and lose the headers along with it.
    private def extract_from_raw(raw_b64 : String, params : Array(Param))
      bytes = begin
        Base64.decode(raw_b64)
      rescue
        return
      end
      return if bytes.empty?

      body_start, sep_len = find_header_body_boundary(bytes)
      header_bytes = body_start ? bytes[0, body_start - sep_len] : bytes
      body_bytes = body_start ? bytes[body_start..] : Bytes.empty

      # Headers are ASCII per RFC 7230; `invalid: :skip` is defensive
      # for malformed exports.
      header_str = String.new(header_bytes, encoding: "UTF-8", invalid: :skip)
      line_sep = header_str.includes?("\r\n") ? "\r\n" : "\n"
      lines = header_str.split(line_sep)
      return if lines.empty?

      content_type = ""
      # First line is the request-line ("METHOD path HTTP/1.1") — skip it.
      lines[1..]?.try &.each do |line|
        next if line.empty?
        idx = line.index(':')
        next unless idx
        name = line[0...idx].strip
        value = line[(idx + 1)..].strip
        next if name.empty?
        if name.downcase == "content-type"
          content_type = value.downcase
          next
        end
        next if skip_header?(name)
        if name.downcase == "cookie"
          parse_cookie_header(value).each do |cookie_name|
            params << Param.new(cookie_name, "", "cookie")
          end
          next
        end
        params << Param.new(name, value, "header")
      end

      return if body_bytes.empty?

      case
      when content_type.includes?("application/json")
        begin
          body_str = String.new(body_bytes, encoding: "UTF-8", invalid: :skip)
          parsed = JSON.parse(body_str)
          if h = parsed.as_h?
            h.each { |k, _| params << Param.new(k, "", "json") }
          end
        rescue e
          logger.debug "Failed to parse Caido JSON body: #{e}"
        end
      when content_type.includes?("application/x-www-form-urlencoded")
        body_str = String.new(body_bytes, encoding: "UTF-8", invalid: :skip)
        parse_query_string(body_str).each do |name|
          params << Param.new(name, "", "form")
        end
      end
    end

    # Returns the byte offset just past the header/body separator and
    # the separator length, or nil if no boundary is present. CRLFCRLF
    # is preferred (standard HTTP wire format) with LFLF as fallback
    # for normalized exports.
    private def find_header_body_boundary(bytes : Bytes) : {Int32?, Int32}
      i = 0
      limit = bytes.size - 3
      while i < limit
        if bytes[i] == 13_u8 && bytes[i + 1] == 10_u8 &&
           bytes[i + 2] == 13_u8 && bytes[i + 3] == 10_u8
          return {i + 4, 4}
        end
        i += 1
      end
      i = 0
      limit = bytes.size - 1
      while i < limit
        if bytes[i] == 10_u8 && bytes[i + 1] == 10_u8
          return {i + 2, 2}
        end
        i += 1
      end
      {nil, 0}
    end

    private def skip_header?(name : String) : Bool
      n = name.downcase
      n == "host" || n == "content-length"
    end

    private def parse_cookie_header(value : String) : Array(String)
      names = [] of String
      value.split(';').each do |pair|
        eq = pair.index('=')
        next unless eq
        name = pair[0...eq].strip
        names << name unless name.empty?
      end
      names
    end
  end
end
