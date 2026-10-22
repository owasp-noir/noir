require "../../engines/c_engine"

module Analyzer::C
  # GNU libmicrohttpd. There is no route registration: `MHD_start_daemon`
  # takes one access handler that receives every request's `url` and
  # `method`, and routes, if at all, by comparing them:
  #
  #     if (0 == strcmp(url, "/login") && 0 == strcmp(method, "POST")) { ... }
  #
  # Each such URI comparison is a route (`strncmp` a prefix one). A daemon
  # whose handler never compares the URI serves every path, reported as `/`
  # with the handler's methods and params. Table-driven dispatch (`strcmp(pages[i].url, url)`)
  # and handlers defined in another file are not followed.
  class Libmicrohttpd < CEngine
    analyzer_for "c_libmicrohttpd"

    COMPARE_RE = /\bstrn?(?:case)?cmp\s*\(/
    DAEMON_RE  = /\bMHD_start_daemon\s*\(/
    URI_ARG_RE = /(?:\b|_)ur[il](?:\b|_)/i

    def analyze_file(path : String) : Array(Endpoint)
      content = read_file_content(path)
      return [] of Endpoint unless content.includes?("MHD_")
      include_callee = callees_needed?
      unit = Noir::CHttpSupport.unit(content)
      source = unit.source
      endpoints = [] of Endpoint

      source.scan(COMPARE_RE) do |match|
        call_start = match.byte_begin(0)
        args, close = Noir::CHttpSupport.call_args(source, match.byte_end(0) - 1) || next
        next unless args.size >= 2
        url = nil
        args.first(2).each_with_index do |arg, i|
          other = args[1 - i]
          url ||= Noir::CHttpSupport.string_value(arg, unit) if !other.includes?('"') && other.matches?(URI_ARG_RE)
        end
        url = Noir::CHttpSupport.route_path(url) || next
        # `strncmp(url, "/api/", 5)` matches the whole subtree.
        url += "*" if match[0].starts_with?("strn")
        endpoints.concat Noir::CHttpSupport.compared_route(unit, path, url, call_start, close, include_callee)
      end
      return endpoints unless endpoints.empty?

      source.scan(DAEMON_RE) do |match|
        args, _ = Noir::CHttpSupport.call_args(source, match.byte_end(0) - 1) || next
        body = Noir::CHttpSupport.handler_body(unit, args[4]?) || next
        line = Noir::CHttpSupport.line_of(unit, match.byte_begin(0))
        endpoints.concat Noir::CHttpSupport.handler_route(unit, path, "/", line, body, include_callee)
      end
      endpoints
    end
  end
end
