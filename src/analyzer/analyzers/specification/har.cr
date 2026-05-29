require "../../../models/analyzer"
require "json"
require "uri"

module Analyzer::Specification
  class Har < Analyzer
    STATIC_EXTENSIONS = {
      ".avif", ".bmp", ".css", ".cur", ".eot", ".gif", ".ico", ".jpeg", ".jpg",
      ".js", ".map", ".mjs", ".otf", ".png", ".svg", ".ttf", ".webmanifest",
      ".webp", ".woff", ".woff2",
    }

    STATIC_CONTENT_TYPES = {
      "application/javascript",
      "application/x-javascript",
      "font/otf",
      "font/ttf",
      "font/woff",
      "font/woff2",
      "image/avif",
      "image/bmp",
      "image/gif",
      "image/jpeg",
      "image/png",
      "image/svg+xml",
      "image/webp",
      "text/css",
    }

    STATIC_PATH_SEGMENTS = {
      "assets", "asset", "static", "public", "dist", "build", "css", "js",
      "javascript", "images", "image", "img", "fonts", "font", "media",
      "favicon",
    }

    def analyze
      locator = CodeLocator.instance
      har_files = locator.all("har-path")

      if har_files.is_a?(Array(String))
        har_files.each do |har_file|
          if File.exists?(har_file)
            data = HAR.from_file(har_file)
            logger.debug "Open #{har_file} file"
            data.entries.each do |entry|
              request_uri = parse_uri(entry.request.url)
              next unless request_uri

              path = endpoint_path(request_uri)
              next unless path
              next if static_asset_request?(entry, request_uri)

              endpoint = Endpoint.new(path, entry.request.method)
              add_query_params(endpoint, entry.request, request_uri)

              is_websocket = websocket_request?(entry.request, request_uri)
              entry.request.headers.each do |header|
                endpoint.params << Param.new(header.name, header.value, "header")
              end

              entry.request.cookies.each do |cookie|
                endpoint.params << Param.new(cookie.name, cookie.value, "cookie")
              end

              add_post_data_params(endpoint, entry.request)

              details = Details.new(PathInfo.new(har_file, 0))
              details.status_code = entry.response.status
              endpoint.details = details
              endpoint.protocol = "ws" if is_websocket
              @result << endpoint
            end
          end
        end
      end

      @result
    end

    private def endpoint_path(request_uri : URI) : String?
      if @url.empty?
        return absolute_endpoint_url(request_uri)
      end

      base_uri = parse_uri(@url)
      return unless base_uri
      return unless matching_origin?(base_uri, request_uri)

      base_path = normalized_uri_path(base_uri)
      request_path = normalized_uri_path(request_uri)
      return unless path_prefix?(base_path, request_path)

      path = request_path[base_path.size..]? || ""
      path = "/#{path}" unless path.starts_with?("/")
      path = "/" if path.empty?
      normalize_dynamic_path(path)
    end

    private def absolute_endpoint_url(request_uri : URI) : String
      scheme = request_uri.scheme.to_s
      host = request_uri.host.to_s
      port = request_uri.port
      path = normalize_dynamic_path(normalized_uri_path(request_uri))
      authority = "#{scheme}://#{host}"
      authority += ":#{port}" if port && port != default_port(request_uri.scheme)
      authority + path
    end

    private def parse_uri(raw_url : String) : URI?
      URI.parse(raw_url)
    rescue
      nil
    end

    private def matching_origin?(base_uri : URI, request_uri : URI) : Bool
      return false unless host_matches?(base_uri.host, request_uri.host)
      return false unless effective_port(base_uri) == effective_port(request_uri)
      compatible_scheme?(base_uri.scheme, request_uri.scheme)
    end

    private def host_matches?(base_host : String?, request_host : String?) : Bool
      return false unless base_host && request_host
      base_host.downcase == request_host.downcase
    end

    private def compatible_scheme?(base_scheme : String?, request_scheme : String?) : Bool
      return false unless base_scheme && request_scheme
      base = base_scheme.downcase
      request = request_scheme.downcase
      return true if base == request
      return true if {"http", "https"}.includes?(base) && {"ws", "wss"}.includes?(request)
      false
    end

    private def effective_port(uri : URI) : Int32?
      return uri.port if uri.port
      default_port(uri.scheme)
    end

    private def default_port(scheme : String?) : Int32?
      case scheme.try(&.downcase)
      when "http", "ws"
        80
      when "https", "wss"
        443
      end
    end

    private def normalized_uri_path(uri : URI) : String
      path = uri.path.presence || "/"
      path = "/#{path}" unless path.starts_with?("/")
      path = path.sub(/\/+\z/, "") unless path == "/"
      path
    end

    private def path_prefix?(base_path : String, request_path : String) : Bool
      return true if base_path == "/"
      request_path == base_path || request_path.starts_with?("#{base_path}/")
    end

    private def normalize_dynamic_path(path : String) : String
      segments = path.split("/")
      normalized = [] of String
      segments.each do |segment|
        if dynamic_segment?(segment, normalized.last?)
          normalized << "{id}"
        else
          normalized << segment
        end
      end
      normalized.join("/")
    end

    private def dynamic_segment?(segment : String, previous : String?) : Bool
      return false if segment.empty?
      previous_segment = previous.try(&.downcase)
      return false if {"api", "version", "versions"}.includes?(previous_segment) && segment.matches?(/\A\d{1,2}\z/)

      segment.matches?(/\A\d+\z/) ||
        segment.matches?(/\A[0-9a-f]{24}\z/i) ||
        segment.matches?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i) ||
        segment.matches?(/\A[0-9A-HJKMNP-TV-Z]{26}\z/)
    end

    private def add_query_params(endpoint : Endpoint, request : HAR::Request, request_uri : URI)
      request.query_string.each do |query|
        add_param_once(endpoint, Param.new(query.name, query.value, "query"))
      end

      return if request_uri.query.to_s.empty?

      URI::Params.parse(request_uri.query.to_s).each do |name, value|
        add_param_once(endpoint, Param.new(name, value, "query"))
      end
    end

    private def add_post_data_params(endpoint : Endpoint, request : HAR::Request)
      post_data = request.post_data
      return unless post_data

      mime_type = request_mime_type(request, post_data)
      param_type = body_param_type(mime_type)

      if params = post_data.params
        params.each do |param|
          add_param_once(endpoint, Param.new(param.name, param.value.to_s, param_type))
        end
      end

      text = post_data.text.to_s
      return if text.empty?

      if multipart_mime?(mime_type)
        collect_multipart_param_names(text).each do |name|
          add_param_once(endpoint, Param.new(name, "", "form"))
        end
      elsif param_type == "json" || looks_like_json?(text)
        collect_json_params(text).each do |name|
          add_param_once(endpoint, Param.new(name, "", "json"))
        end
      elsif urlencoded_mime?(mime_type) || looks_like_form?(text)
        URI::Params.parse(text).each do |name, value|
          add_param_once(endpoint, Param.new(name, value, "form"))
        end
      end
    end

    private def request_mime_type(request : HAR::Request, post_data : HAR::PostData) : String
      mime_type = post_data.mime_type.to_s
      return mime_type unless mime_type.empty?

      request.headers.each do |header|
        return header.value if header.name.downcase == "content-type"
      end

      ""
    end

    private def body_param_type(mime_type : String) : String
      normalized = normalized_mime_type(mime_type)
      return "json" if normalized == "application/json" || normalized.ends_with?("+json")
      return "form" if normalized == "application/x-www-form-urlencoded" || normalized == "multipart/form-data"
      "body"
    end

    private def normalized_mime_type(mime_type : String) : String
      mime_type.downcase.split(";").first?.try(&.strip) || ""
    end

    private def multipart_mime?(mime_type : String) : Bool
      normalized_mime_type(mime_type) == "multipart/form-data"
    end

    private def urlencoded_mime?(mime_type : String) : Bool
      normalized_mime_type(mime_type) == "application/x-www-form-urlencoded"
    end

    private def looks_like_json?(text : String) : Bool
      stripped = text.strip
      (stripped.starts_with?("{") && stripped.ends_with?("}")) ||
        (stripped.starts_with?("[") && stripped.ends_with?("]"))
    end

    private def looks_like_form?(text : String) : Bool
      text.includes?("=") && !text.includes?("\n")
    end

    private def collect_json_params(text : String) : Array(String)
      names = [] of String
      value = JSON.parse(text)
      collect_json_names(value, names)
      names.uniq
    rescue
      [] of String
    end

    private def collect_json_names(value : JSON::Any, names : Array(String), prefix : String? = nil)
      case raw = value.raw
      when Hash
        raw.each do |key, child|
          name = prefix ? "#{prefix}.#{key}" : key.to_s
          names << name
          collect_json_names(child, names, name)
        end
      when Array
        raw.each do |child|
          collect_json_names(child, names, prefix)
        end
      end
    end

    private def collect_multipart_param_names(text : String) : Array(String)
      names = [] of String
      text.scan(/content-disposition:[^\r\n]*\bname=(?:"([^"]+)"|'([^']+)'|([^;\r\n]+))/i) do |match|
        name = match[1]? || match[2]? || match[3]? || ""
        name = name.strip
        names << name unless name.empty?
      end
      names.uniq
    end

    private def add_param_once(endpoint : Endpoint, param : Param)
      return if endpoint.params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      endpoint.params << param
    end

    private def websocket_request?(request : HAR::Request, request_uri : URI) : Bool
      return true if {"ws", "wss"}.includes?(request_uri.scheme.try(&.downcase))

      request.headers.any? do |header|
        header.name.downcase == "upgrade" && header.value.downcase == "websocket"
      end
    end

    private def static_asset_request?(entry : HAR::Entry, request_uri : URI) : Bool
      method = entry.request.method.upcase
      return false unless method == "GET" || method == "HEAD"
      return false if websocket_request?(entry.request, request_uri)
      return false if entry.request.post_data

      extension = File.extname(request_uri.path.to_s).downcase
      return true if STATIC_EXTENSIONS.includes?(extension)

      return false unless static_path_signal?(request_uri)

      content_type = response_content_type(entry)
      return false if content_type.empty?

      STATIC_CONTENT_TYPES.includes?(content_type)
    end

    private def static_path_signal?(request_uri : URI) : Bool
      return false unless request_uri.query.to_s.empty?

      request_uri.path.to_s.split("/").any? do |segment|
        STATIC_PATH_SEGMENTS.includes?(segment.downcase)
      end
    end

    private def response_content_type(entry : HAR::Entry) : String
      entry.response.content_type.to_s.downcase
    rescue
      ""
    end
  end
end
