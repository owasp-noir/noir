require "uri"
require "../../../models/analyzer"
require "../../../utils/tnetstring"

module Analyzer::Specification
  class Mitmproxy < Analyzer
    # mitmproxy's `version` field has changed shape across releases:
    # pre-3.x stored a `[major, minor, patch]` list, while modern
    # versions (3.x through current ≥20) store a single integer. We
    # ignore anything that decodes to a list whose major < 3 — those
    # files predate the dict-based flow layout this analyzer
    # understands. Modern integer versions are accepted as-is.
    MIN_LEGACY_MAJOR = 3_i64

    def analyze
      locator = CodeLocator.instance
      paths = locator.all("mitmproxy-path")
      return @result unless paths.is_a?(Array(String))

      paths.each do |path|
        next unless File.exists?(path)
        begin
          bytes = read_binary(path)
          process_file(path, bytes)
        rescue ex
          logger.debug "Failed to parse mitmproxy flow #{path}: #{ex.message}"
        end
      end

      @result
    end

    private def read_binary(path : String) : Bytes
      size = File.size(path).to_i
      buffer = Bytes.new(size)
      File.open(path, &.read_fully(buffer))
      buffer
    end

    private def process_file(path : String, bytes : Bytes)
      pos = 0
      while pos < bytes.size
        flow, pos = Tnetstring.parse(bytes, pos)
        process_flow(path, flow)
      end
    end

    private def process_flow(path : String, flow : Tnetstring::Value)
      return unless flow.is_a?(Hash)

      type_value = flow["type"]?
      return unless type_value.is_a?(String) && type_value == "http"

      version = flow["version"]?
      if version.is_a?(Array) && (major = version[0]?).is_a?(Int64) && major < MIN_LEGACY_MAJOR
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
      full_url = base_url + raw_path

      # Match HAR's filter semantics: only emit endpoints that fall
      # under the user-provided --url. Without a URL we cannot infer
      # what slice of the capture the user cares about.
      return if @url == ""
      return unless full_url.includes?(@url)

      endpoint_path = full_url.gsub(@url, "")
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

          endpoint.params << Param.new(hname, hvalue, "header")

          lname = hname.downcase
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

      endpoint.details = Details.new(PathInfo.new(path, 0))
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
