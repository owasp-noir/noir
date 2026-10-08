require "../../engines/c_engine"

module Analyzer::C
  # CivetWeb. Handlers are registered per URI pattern:
  #
  #     mg_set_request_handler(ctx, "/api/items", ItemsHandler, 0);
  #     mg_set_websocket_handler(ctx, "/ws", connect, ready, data, close, 0);
  #     server.addHandler("/a", h_a);              // C++ CivetServer wrapper
  #
  # A C handler is one function for every method, so the methods are the ones
  # it compares `request_method` against (GET if it never does). A C++
  # handler is a `CivetHandler` subclass whose `handleGet`/`handlePost`/...
  # overrides are the methods (`handleAll` alone serves them all).
  class Civetweb < CEngine
    analyzer_for "c_civetweb"

    REGISTER_RE      = /\b(mg_set_request_handler|mg_set_websocket_handler(?:_with_subprotocols)?|addHandler|addWebSocketHandler)\s*\(/
    HANDLE_METHOD_RE = /\bhandle(Get|Post|Put|Delete|Patch|Head|Options)\s*\(/
    ALL_METHODS      = %w[GET POST PUT DELETE PATCH]

    def analyze_file(path : String) : Array(Endpoint)
      content = read_file_content(path)
      return [] of Endpoint unless content.includes?("mg_set_") || content.includes?("Civet")
      include_callee = callees_needed?
      unit = Noir::CHttpSupport.unit(content)
      source = unit.source
      endpoints = [] of Endpoint

      source.scan(REGISTER_RE) do |match|
        args, _ = Noir::CHttpSupport.call_args(source, match.byte_end(0) - 1) || next
        call = match[1]
        c_api = call.starts_with?("mg_")
        url = Noir::CHttpSupport.route_path(Noir::CHttpSupport.string_value(args[c_api ? 1 : 0]?, unit)) || next
        line = Noir::CHttpSupport.line_of(unit, match.byte_begin(0))

        if call.downcase.includes?("websocket")
          endpoints.concat Noir::CHttpSupport.endpoints(path, url, line, [] of String, "", nil, false, "ws")
          next
        end

        handler = args[c_api ? 2 : 1]?
        if c_api
          body = Noir::CHttpSupport.handler_body(unit, handler)
          endpoints.concat Noir::CHttpSupport.handler_route(unit, path, url, line, body, include_callee)
        else
          body = handler.try { |h| handler_class_body(source, h.strip.lchop('&').lchop('*').strip) }
          methods = [] of String
          body[0].scan(HANDLE_METHOD_RE) { |m| methods << m[1].upcase } if body
          # Only `handleAll` overridden: it serves every verb.
          if body && methods.empty? && body[0].includes?("handleAll")
            methods = Noir::CHttpSupport.methods_in(body[0])
            methods = ALL_METHODS if methods.empty?
          end
          endpoints.concat Noir::CHttpSupport.handler_route(unit, path, url, line, body, include_callee, methods.uniq)
        end
      end

      endpoints
    end

    # Body of the `CivetHandler` subclass behind `addHandler`'s handler
    # argument: `new FooHandler()` or a variable declared as `FooHandler h;`
    # in the same file.
    private def handler_class_body(source : String, handler : String) : Tuple(String, Int32)?
      class_name = handler.lchop("new").strip[/\A\w+/]? if handler.starts_with?("new ")
      class_name ||= source.scan(/\b([A-Za-z_]\w*)\s*[*&]?\s*\b#{Regex.escape(handler)}\s*[;=({]/)
        .map(&.[1]).find { |name| !Noir::CppCalleeExtractor::RESERVED.includes?(name) }
      return unless class_name
      decl = source.match(/\b(?:class|struct)\s+#{Regex.escape(class_name)}\b[^;{]*\{/) || return
      Noir::CppCalleeExtractor.extract_block_after(source, decl.byte_begin(0))
    end
  end
end
