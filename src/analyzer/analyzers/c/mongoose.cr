require "../../../models/analyzer"
require "../../../miniparsers/c_http_support"

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
  class Mongoose < Analyzer
    analyzer_for "c_mongoose"

    ROUTE_CALL_RE = /\bmg_(http_match_uri|register_http_endpoint|match|strcmp|vcmp|vcasecmp|globmatch)\s*\(/

    def analyze
      include_callee = callees_needed?
      files = get_files_by_extensions(Noir::CHttpSupport::EXTENSIONS)
      ordered_scan_files(files) do |path|
        next if Noir::CHttpSupport.vendored?(path)
        content = read_file_content(path)
        analyze_file(path, content, include_callee) if content.includes?("mg_")
      end.each { |endpoints| result.concat(endpoints) }
      result
    end

    private def analyze_file(path : String, content : String, include_callee : Bool) : Array(Endpoint)
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
          line = Noir::CppCalleeExtractor.line_number_for(source, call_start)
          handler = Noir::CHttpSupport.handler_body(unit, args[2]?)
          endpoints.concat Noir::CHttpSupport.handler_route(unit, path, url, line, handler, include_callee)
          next
        end

        # Only comparisons against the request URI are routes; `mg_match`
        # also matches MQTT topics and URLs.
        next unless kind == "http_match_uri" || args.any?(&.includes?("uri"))
        literal = args.compact_map { |arg| Noir::CHttpSupport.string_value(arg, unit) }.first?
        url = Noir::CHttpSupport.route_path(literal) || next
        endpoints.concat Noir::CHttpSupport.compared_route(unit, path, url, call_start, close, include_callee)
      end

      endpoints
    end
  end
end
