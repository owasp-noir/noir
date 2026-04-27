require "../../models/tagger"
require "../../models/endpoint"

class McpTagger < Tagger
  LEGACY_SSE_SEGMENT      = "sse"
  LEGACY_MESSAGE_SEGMENTS = ["message", "messages"]

  def initialize(options : Hash(String, YAML::Any))
    super
    @name = "mcp"
  end

  def perform(endpoints : Array(Endpoint))
    legacy_prefixes = legacy_mcp_prefixes(endpoints)

    endpoints.each do |endpoint|
      next unless mcp_endpoint?(endpoint, legacy_prefixes)

      tag = Tag.new("mcp", "Model Context Protocol endpoint for tool and resource communication, often using Streamable HTTP or legacy SSE transports.", "MCP")
      endpoint.add_tag(tag)
    end
  end

  private def mcp_endpoint?(endpoint : Endpoint, legacy_prefixes : Set(String)) : Bool
    path = normalized_path(endpoint.url)
    segments = path_segments(path)

    return true if segments.includes?("mcp")
    return true if path.includes?("model-context-protocol")

    legacy_mcp_endpoint?(endpoint, segments, legacy_prefixes)
  end

  private def legacy_mcp_prefixes(endpoints : Array(Endpoint)) : Set(String)
    sse_prefixes = Set(String).new
    message_prefixes = Set(String).new

    endpoints.each do |endpoint|
      segments = path_segments(normalized_path(endpoint.url))
      next if segments.empty?

      prefix = legacy_prefix(segments)
      last_segment = segments[-1]
      method = endpoint.method.upcase

      if method == "GET" && last_segment == LEGACY_SSE_SEGMENT
        sse_prefixes.add(prefix)
      elsif method == "POST" && LEGACY_MESSAGE_SEGMENTS.includes?(last_segment)
        message_prefixes.add(prefix)
      end
    end

    sse_prefixes & message_prefixes
  end

  private def legacy_mcp_endpoint?(endpoint : Endpoint, segments : Array(String), legacy_prefixes : Set(String)) : Bool
    return false if segments.empty?

    last_segment = segments[-1]
    prefix = legacy_prefix(segments)
    method = endpoint.method.upcase

    return true if method == "GET" && last_segment == LEGACY_SSE_SEGMENT && legacy_prefixes.includes?(prefix)
    return true if method == "POST" && LEGACY_MESSAGE_SEGMENTS.includes?(last_segment) && legacy_prefixes.includes?(prefix)

    false
  end

  private def normalized_path(url : String) : String
    path = url.strip

    if scheme_index = path.index("://")
      remainder = path[(scheme_index + 3)..]
      if slash_index = remainder.index("/")
        path = remainder[slash_index..]
      else
        path = "/"
      end
    end

    path = path.split("?", 2)[0]
    path = path.split("#", 2)[0]
    path = "/" if path.empty?
    path.downcase
  end

  private def path_segments(path : String) : Array(String)
    path.split("/").reject(&.empty?)
  end

  private def legacy_prefix(segments : Array(String)) : String
    return "" if segments.size <= 1

    segments[0...-1].join("/")
  end
end
