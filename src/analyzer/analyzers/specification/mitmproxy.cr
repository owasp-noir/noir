require "uri"
require "../../engines/specification_engine"
require "../../../utils/tnetstring"

module Analyzer::Specification
  class Mitmproxy < SpecificationEngine
    analyzer_for "mitmproxy"

    # mitmproxy's `version` field has changed shape across releases:
    # pre-3.x stored a `[major, minor, patch]` list, while modern
    # versions (3.x through current ≥20) store a single integer. A
    # list-shaped version with `major < 3` predates the dict-based
    # flow layout this analyzer understands.
    LEGACY_LIST_MIN_MAJOR = 3_i64

    def analyze
      each_spec_file(Noir::LocatorKeys::MITMPROXY_PATH) do |path|
        bytes = read_binary(path)
        process_file(path, bytes)
      end

      @result
    end

    private def read_binary(path : String) : Bytes
      size = File.size(path).to_i
      buffer = Bytes.new(size)
      File.open(path, &.read_fully(buffer))
      buffer
    end

    # Stream the flow file one tnetstring at a time. A truncated or
    # malformed record at any offset stops the loop, but the flows we
    # already pulled out before the bad byte are preserved — mitmproxy
    # writes each flow independently, so partial captures are still
    # worth importing.
    private def process_file(path : String, bytes : Bytes)
      pos = 0
      while pos < bytes.size
        begin
          flow, pos = Tnetstring.parse(bytes, pos)
        rescue ex : Tnetstring::ParseError
          logger.debug "Stopping mitmproxy parse at offset #{pos} in #{path}: #{ex.message}"
          break
        end
        process_flow(path, flow)
      end
    end

    private def process_flow(path : String, flow : Tnetstring::Value)
      return unless flow.is_a?(Hash)

      type_value = flow["type"]?
      return unless type_value.is_a?(String) && type_value == "http"

      version = flow["version"]?
      if version.is_a?(Array) && (major = version[0]?).is_a?(Int64) && major < LEGACY_LIST_MIN_MAJOR
        logger.debug "Skipping mitmproxy flow with unsupported version #{major} in #{path}"
        return
      end

      request = flow["request"]?
      return unless request.is_a?(Hash)

      method = (stringify(request["method"]?) || "GET").upcase
      raw_path = stringify(request["path"]?) || "/"
      host = stringify(request["host"]?) || ""
      scheme = stringify(request["scheme"]?) || "http"
      port_raw = request["port"]?
      port = port_raw.is_a?(Int64) ? port_raw : nil

      base_url = build_url(scheme, host, port)
      # The query string is emitted as `query` params below, so it does not
      # belong in the URL as well: leaving it in duplicated every parameter
      # and split one endpoint into one-per-captured-value
      # (`/search?q=a`, `/search?q=b`, …). HAR reports `uri.path` for the
      # same reason.
      path_only, _ = split_query(raw_path)
      path_only = "/" if path_only.empty?
      full_url = base_url + path_only

      # Match HAR's semantics. With `--url` the capture is filtered down to
      # that origin and the prefix is stripped; without one, HAR emits the
      # absolute URL rather than dropping the flow — a mitmproxy dump scanned
      # on its own used to produce zero endpoints, which is the whole reason
      # someone points noir at one.
      if @url.empty?
        endpoint_path = full_url
      else
        return unless (base_url + raw_path).includes?(@url)

        # Strip the user URL as a LEADING prefix only — gsub removed every
        # occurrence, mangling paths where the prefix recurs (e.g. a redirect param).
        endpoint_path = full_url.starts_with?(@url) ? full_url[@url.size..]? || "" : full_url
      end
      endpoint_path = "/#{endpoint_path}" unless endpoint_path.starts_with?("/") || endpoint_path.includes?("://")
      endpoint_path = "/" if endpoint_path.empty?
      endpoint = Endpoint.new(endpoint_path, method)

      headers = request["headers"]?
      content_type = ""
      is_websocket = false

      if headers.is_a?(Array)
        headers.each do |entry|
          next unless entry.is_a?(Array) && entry.size == 2
          hname = stringify(entry[0])
          hvalue = stringify(entry[1])
          next unless hname && hvalue

          lname = hname.downcase
          # A mitmproxy capture of an HTTP/2 or HTTP/3 flow carries the
          # request line as `:method` / `:scheme` / `:authority` / `:path`
          # pseudo-headers. They are not parameters a request can set, and
          # `host` / `content-length` are the HTTP/1 equivalents the Burp and
          # Caido analyzers already skip.
          unless lname.starts_with?(':') || lname == "host" || lname == "content-length"
            endpoint.params << Param.new(hname, hvalue, "header")
          end

          case lname
          when "content-type"
            content_type = hvalue
          when "cookie"
            split_cookies(hvalue).each do |(cname, cvalue)|
              endpoint.params << Param.new(cname, cvalue, "cookie")
            end
          when "upgrade"
            is_websocket = true if hvalue.downcase == "websocket"
          end
        end
      end

      _, query_string = split_query(raw_path)
      if query_string
        parse_query(query_string).each do |(qname, qvalue)|
          endpoint.params << Param.new(qname, qvalue, "query")
        end
      end

      body = stringify(request["content"]?)
      if body && !body.empty?
        param_type = body_param_type(content_type)
        if param_type == "form"
          parse_query(body).each do |(bname, bvalue)|
            endpoint.params << Param.new(bname, bvalue, "form")
          end
        else
          endpoint.params << Param.new("body", body, param_type)
        end
      end

      endpoint.details = Details.new(PathInfo.new(path))
      endpoint.protocol = "ws" if is_websocket
      @result << endpoint
    end

    private def stringify(value : Tnetstring::Value?) : String?
      case value
      when String  then value
      when Int64   then value.to_s
      when Float64 then value.to_s
      when Bool    then value.to_s
      end
    end

    private def build_url(scheme : String, host : String, port : Int64?) : String
      return "" if host.empty?
      if port && !default_port?(scheme, port)
        "#{scheme}://#{host}:#{port}"
      else
        "#{scheme}://#{host}"
      end
    end

    private def default_port?(scheme : String, port : Int64) : Bool
      (scheme == "http" && port == 80) || (scheme == "https" && port == 443)
    end

    private def split_query(path : String) : Tuple(String, String?)
      idx = path.index('?')
      return {path, nil} unless idx
      {path[0...idx], path[(idx + 1)..]}
    end

    private def parse_query(query : String) : Array(Tuple(String, String))
      result = [] of Tuple(String, String)
      query.split('&').each do |pair|
        next if pair.empty?
        eq = pair.index('=')
        if eq
          name = pair[0...eq]
          value = pair[(eq + 1)..]
        else
          name = pair
          value = ""
        end
        result << {decode_form(name), decode_form(value)}
      end
      result
    end

    private def split_cookies(header : String) : Array(Tuple(String, String))
      result = [] of Tuple(String, String)
      header.split(';').each do |part|
        part = part.strip
        next if part.empty?
        eq = part.index('=')
        if eq
          result << {part[0...eq].strip, part[(eq + 1)..].strip}
        else
          result << {part, ""}
        end
      end
      result
    end

    private def decode_form(s : String) : String
      URI.decode_www_form(s)
    rescue
      s
    end

    private def body_param_type(content_type : String) : String
      ct = content_type.downcase
      return "json" if ct.includes?("application/json")
      return "form" if ct.includes?("application/x-www-form-urlencoded")
      "body"
    end
  end
end
