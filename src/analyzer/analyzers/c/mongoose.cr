require "../../engines/c_engine"

module Analyzer::C
  # Cesanta Mongoose. One event handler serves every request and routes by
  # comparing the URI inside it:
  #
  #     if (mg_match(hm->uri, mg_str("/api/login"), NULL)) { ... }   // 7.12+
  #     else if (mg_http_match_uri(hm, "/api/#")) { ... }            // 7.x
  #     if (mg_vcmp(&hm->uri, "/api/sum") == 0) { ... }               // 6.x
  #     mg_register_http_endpoint(c, "/api/v1/sum", handle_sum);       // 6.x
  #
  # The method comes from the same `if` condition, else from the branch
  # body, else GET. Params are read from the branch body and the same-file
  # helpers it calls.
  class Mongoose < CEngine
    analyzer_for "c_mongoose"

    ROUTE_CALL_RE = /\bmg_(http_match_uri|register_http_endpoint|match|strcmp|vcmp|vcasecmp|globmatch)\s*\(/

    def analyze_file(path : String) : Array(Endpoint)
      content = read_file_content(path)
      return [] of Endpoint unless content.includes?("mg_")
      include_callee = callees_needed?
      unit = Noir::CHttpSupport.unit(content)
      source = unit.source
      endpoints = [] of Endpoint

      source.scan(ROUTE_CALL_RE) do |match|
        call_start = match.byte_begin(0)
        open_paren = match.byte_end(0) - 1
        args, close = Noir::CHttpSupport.call_args(source, open_paren) || next
        kind = match[1]

        if kind == "register_http_endpoint"
          url = Noir::CHttpSupport.route_path(Noir::CHttpSupport.string_value(args[1]?, unit)) || next
          line = Noir::CHttpSupport.line_of(unit, call_start)
          handler = Noir::CHttpSupport.handler_body(unit, args[2]?)
          endpoints.concat Noir::CHttpSupport.handler_route(unit, path, url, line, handler, include_callee)
          next
        end

        # Only comparisons against the request URI (`hm->uri`) are routes;
        # `mg_match` also matches MQTT topics and URLs.
        next unless kind == "http_match_uri" || args.any? { |arg| !arg.includes?('"') && arg.matches?(/\buri\b/) }
        literal = args.compact_map { |arg| Noir::CHttpSupport.string_value(arg, unit) }.first?
        url = Noir::CHttpSupport.route_path(literal) || next
        endpoints.concat Noir::CHttpSupport.compared_route(unit, path, url, call_start, close, include_callee)
      end

      endpoints
    end
  end
end
