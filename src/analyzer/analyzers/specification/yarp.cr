require "../../engines/specification_engine"
require "../csharp/common"

module Analyzer::Specification
  # YARP (`Yarp.ReverseProxy`): each route publishes `Match.Path` for the
  # `Match.Methods` verbs, or for any verb when there is no method list.
  # Read from the `ReverseProxy:Routes` config section and from
  # `new RouteMatch { ... }` initializers in C#.
  class Yarp < SpecificationEngine
    analyzer_for "yarp"

    ROUTE_MATCH_RE = /\b(?:new\s+RouteMatch|Match\s*=\s*new)\s*(?:\(\s*\))?\s*\{/
    CODE_PATH_RE   = /\bPath\s*=\s*"([^"]*)"/
    CODE_LIST_RE   = /\b(Methods|Hosts)\s*=\s*(?:new\b[^{;]*\{([^}]*)\}|\[([^\]]*)\])/
    QUOTED_RE      = /"([^"]+)"/
    PLACEHOLDER_RE = /\{([^{}]*)\}/

    def analyze
      each_spec_file_with_details(Noir::LocatorKeys::YARP_SPEC) do |path, details|
        content = read_file_content(path)
        if path.ends_with?(".cs")
          process_code(content, details) unless CSharp::Common.csharp_test_path?(base_relative_path(path))
        else
          process_config(content, details)
        end
      end

      @result
    end

    private def process_config(content : String, details : Details)
      json = strip_jsonc(content)
      return unless root = parse_json_lenient(json).as_h?
      routes = root["ReverseProxy"]?.try(&.as_h?).try(&.["Routes"]?)
      return unless routes

      index = Noir::SpecLineIndex.json(json, "ReverseProxy")
      list = routes.as_h?.try(&.to_a) || routes.as_a?.try(&.map { |r| {"", r} }) || [] of {String, JSON::Any}
      list.each do |route_id, route|
        next unless route_h = route.as_h?
        next unless match = route_h["Match"]?.try(&.as_h?)
        next unless path = match["Path"]?.try(&.as_s?).presence

        params = [] of Param
        match["QueryParameters"]?.try(&.as_a?).try(&.each { |q| add_param(params, q["Name"]?.try(&.as_s?) || "", "query") if q.as_h? })
        match["Headers"]?.try(&.as_a?).try(&.each { |h| add_param(params, h["Name"]?.try(&.as_s?) || "", "header") if h.as_h? })

        emit(path, json_strings(match["Methods"]?), json_strings(match["Hosts"]?),
          route_h["ClusterId"]?.try(&.as_s?), params, details_at(details, index.line("ReverseProxy", "Routes", route_id)))
      end
    end

    # Scans the comment-blanked source, so a commented-out route is not read,
    # and closes each initializer with the lexer's string-aware brace match.
    private def process_code(content : String, details : Details)
      lexer = Noir::CSharpLexer.new(content)
      code = lexer.code_source
      chars = code.chars
      byte_pos = 0
      char_pos = 0
      line = 1
      code.scan(ROUTE_MATCH_RE) do |m|
        open_byte = m.byte_end(0) - 1
        segment = code.byte_slice(byte_pos, open_byte - byte_pos)
        char_pos += segment.size
        line += segment.count('\n')
        byte_pos = open_byte
        next unless close = lexer.matching_delimiter(char_pos)

        block = chars[(char_pos + 1)...close].join
        next unless path = CODE_PATH_RE.match(block).try(&.[1]).presence

        lists = {"Methods" => [] of String, "Hosts" => [] of String}
        block.scan(CODE_LIST_RE) do |list|
          body = list[2]? || list[3]? || ""
          body.scan(QUOTED_RE) { |q| lists[list[1]] << q[1] }
        end
        emit(path, lists["Methods"], lists["Hosts"], nil, [] of Param, details_at(details, line))
      end
    end

    private def emit(path : String, methods : Array(String), hosts : Array(String),
                     cluster : String?, params : Array(Param), details : Details)
      url = path.gsub(PLACEHOLDER_RE) do |_, m|
        raw = m[1]
        raw.starts_with?('*') ? "*" : "{#{CSharp::Common.route_placeholder_name(raw)}}"
      end
      methods = methods.map(&.upcase)
      methods = ["ANY"] if methods.empty?

      methods.each do |method|
        endpoint = Endpoint.new(url, method, params.dup, details)
        # `add_tag` keeps one tag per name, so the hosts share one.
        endpoint.add_tag(Tag.new("yarp-host", hosts.join(", "), "yarp_analyzer")) unless hosts.empty?
        if cluster = cluster.presence
          endpoint.add_tag(Tag.new("yarp-cluster", cluster, "yarp_analyzer"))
        end
        @result << endpoint
      end
    end
  end
end
