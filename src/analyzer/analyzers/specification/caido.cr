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
      if raw_value = obj["raw"]?.try(&.as_s?)
        if raw_value.size > 0
          decoded = decode_raw(raw_value)
          if decoded
            extract_from_raw(decoded, params)
          end
        end
      end

      @result << Endpoint.new(normalized_path, method, params, details)
    end

    private def decode_raw(raw : String) : String?
      Base64.decode_string(raw)
    rescue
      nil
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
    # for known content types. Best-effort: malformed or binary
    # bodies are silently skipped.
    private def extract_from_raw(raw : String, params : Array(Param))
      separator = raw.includes?("\r\n\r\n") ? "\r\n\r\n" : "\n\n"
      head, _, body = raw.partition(separator)
      line_sep = head.includes?("\r\n") ? "\r\n" : "\n"
      lines = head.split(line_sep)
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

      return if body.empty?

      case
      when content_type.includes?("application/json")
        begin
          parsed = JSON.parse(body)
          if h = parsed.as_h?
            h.each { |k, _| params << Param.new(k, "", "json") }
          end
        rescue
        end
      when content_type.includes?("application/x-www-form-urlencoded")
        parse_query_string(body).each do |name|
          params << Param.new(name, "", "form")
        end
      end
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
