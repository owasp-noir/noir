require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"

module Noir
  # Tree-sitter-backed Hapi extractor.
  #
  # Hapi routes are object-literal configs passed to
  # `server.route({...})` (or an array of them):
  #
  # ```
  # server.route({
  #     method: 'GET',
  #     path: '/users/{id}',
  #     handler: (request, h) => { ... }
  # });
  #
  # server.route([
  #     { method: 'POST', path: '/users', handler: ... },
  #     { method: ['PUT', 'PATCH'], path: '/users/{id}', handler: ... },
  # ]);
  # ```
  #
  # Recognised:
  #
  #   * Single object or array-of-objects route config.
  #   * `method:` as a string, an array of strings, or `'*'`
  #     (any-method — fans out to GET/POST/PUT/DELETE/PATCH).
  #   * `path:` as a string literal.
  #   * `handler:` arrow function — body scanned for
  #     `request.query.X`, `request.headers['x']` /
  #     `request.headers.x`, `request.payload`, `request.state.X`.
  #
  # Out of scope for this first cut:
  #
  #   * `options.validate` constraint synthesis (Joi schemas).
  #   * Pre-handler chains (`pre: [...]`).
  #   * `server.route` registered through plugins / wildcards in the
  #     receiver (`api.route`, etc.) — receiver name is ignored, so
  #     only the `.route(...)` shape matters.
  module TreeSitterHapiExtractor
    extend self

    ANY_METHOD_VERBS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    HTTP_VERBS = Set{
      "GET", "POST", "PUT", "DELETE", "PATCH",
      "HEAD", "OPTIONS",
    }

    struct Route
      getter verb : String
      getter path : String
      getter line : Int32
      getter? has_body : Bool
      getter query_params : Array(String)
      getter header_params : Array(String)
      getter cookie_params : Array(String)

      def initialize(@verb, @path, @line, @has_body,
                     @query_params, @header_params, @cookie_params)
      end
    end

    def extract_routes(source : String) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_javascript(source) do |root|
        walk(root, source, routes)
      end
      routes
    end

    # ---- traversal --------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, source : String, routes : Array(Route))
      if Noir::TreeSitter.node_type(node) == "call_expression" && route_call?(node, source)
        emit_routes(node, source, routes)
        return
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, routes)
      end
    end

    private def route_call?(call : LibTreeSitter::TSNode, source : String) : Bool
      callee = first_named_child(call)
      return false unless callee
      return false unless Noir::TreeSitter.node_type(callee) == "member_expression"

      Noir::TreeSitter.each_named_child(callee) do |child|
        if Noir::TreeSitter.node_type(child) == "property_identifier"
          return Noir::TreeSitter.node_text(child, source) == "route"
        end
      end
      false
    end

    private def emit_routes(call : LibTreeSitter::TSNode, source : String, routes : Array(Route))
      args = arguments_node(call)
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        case Noir::TreeSitter.node_type(arg)
        when "object"
          emit_route_object(arg, source, routes)
        when "array"
          Noir::TreeSitter.each_named_child(arg) do |elem|
            emit_route_object(elem, source, routes) if Noir::TreeSitter.node_type(elem) == "object"
          end
        end
      end
    end

    private def emit_route_object(obj : LibTreeSitter::TSNode, source : String, routes : Array(Route))
      methods = [] of String
      path : String? = nil
      handler : LibTreeSitter::TSNode? = nil

      Noir::TreeSitter.each_named_child(obj) do |pair|
        next unless Noir::TreeSitter.node_type(pair) == "pair"
        key, value = pair_key_value(pair, source)
        next unless value

        case key
        when "method"
          collect_method_values(value, source, methods)
        when "path"
          path = decode_string(value, source) if Noir::TreeSitter.node_type(value) == "string"
        when "handler"
          handler = value
        end
      end

      resolved_path = path
      return if resolved_path.nil? || methods.empty?
      line = Noir::TreeSitter.node_start_row(obj)

      query_params = [] of String
      header_params = [] of String
      cookie_params = [] of String
      has_body = false

      if handler
        scan_handler(handler, source) do |kind, value|
          case kind
          when :query  then query_params << value
          when :header then header_params << value
          when :cookie then cookie_params << value
          when :body   then has_body = true
          end
        end
      end

      methods.each do |verb|
        routes << Route.new(verb, resolved_path, line, has_body,
          query_params, header_params, cookie_params)
      end
    end

    private def pair_key_value(pair : LibTreeSitter::TSNode, source : String) : Tuple(String, LibTreeSitter::TSNode?)
      key = ""
      value : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(pair) do |child|
        ty = Noir::TreeSitter.node_type(child)
        case ty
        when "property_identifier", "identifier"
          key = Noir::TreeSitter.node_text(child, source) if key.empty?
        when "string"
          if key.empty?
            key = decode_string(child, source)
          else
            value = child
          end
        else
          value = child if value.nil?
        end
      end
      {key, value}
    end

    private def collect_method_values(value : LibTreeSitter::TSNode, source : String, sink : Array(String))
      case Noir::TreeSitter.node_type(value)
      when "string"
        text = decode_string(value, source).upcase
        if text == "*"
          sink.concat(ANY_METHOD_VERBS)
        elsif HTTP_VERBS.includes?(text)
          sink << text
        end
      when "array"
        Noir::TreeSitter.each_named_child(value) do |elem|
          if Noir::TreeSitter.node_type(elem) == "string"
            text = decode_string(elem, source).upcase
            sink << text if HTTP_VERBS.includes?(text)
          end
        end
      end
    end

    # ---- handler-body scan ------------------------------------------

    private def scan_handler(node : LibTreeSitter::TSNode, source : String, &block : Symbol, String ->)
      ty = Noir::TreeSitter.node_type(node)

      case ty
      when "member_expression"
        chain = navigation_chain(node, source)
        if chain.size >= 3 && chain[0] == "request"
          # `request.query.X`, `request.state.X`, `request.headers.X`,
          # `request.payload.X` — emit just the leaf as the param
          # name. Note `request.params.X` is intentionally skipped:
          # the URL placeholder already provides the path param via
          # the optimizer.
          tail = chain.last
          case chain[1]
          when "query"   then block.call(:query, tail)
          when "headers" then block.call(:header, tail)
          when "state"   then block.call(:cookie, tail)
          when "payload" then block.call(:body, "")
          end
        elsif chain.size >= 2 && chain == ["request", "payload"]
          # Top-level `request.payload` access (without a sub-key).
          block.call(:body, "")
        end
      when "subscript_expression"
        target = first_named_child(node)
        if target
          base_chain = navigation_chain(target, source)
          if base_chain.size >= 2 && base_chain[0] == "request"
            key = subscript_string_key(node, source)
            if key
              case base_chain[1]
              when "query"   then block.call(:query, key)
              when "headers" then block.call(:header, key)
              when "state"   then block.call(:cookie, key)
              end
            end
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        scan_handler(child, source, &block)
      end
    end

    # Collapse a `member_expression` chain into `["a", "b", "c"]`
    # for `a.b.c`. Returns an empty array on any non-identifier
    # piece (function calls, computed properties, etc.).
    private def navigation_chain(node : LibTreeSitter::TSNode, source : String) : Array(String)
      chain = [] of String
      collect_chain(node, source, chain)
      chain
    end

    private def collect_chain(node : LibTreeSitter::TSNode, source : String, chain : Array(String))
      case Noir::TreeSitter.node_type(node)
      when "identifier"
        chain << Noir::TreeSitter.node_text(node, source)
      when "member_expression"
        Noir::TreeSitter.each_named_child(node) do |child|
          ty = Noir::TreeSitter.node_type(child)
          case ty
          when "identifier", "member_expression"
            collect_chain(child, source, chain)
          when "property_identifier"
            chain << Noir::TreeSitter.node_text(child, source)
          else
            chain.clear
            chain << ""
            return
          end
        end
      else
        chain.clear
        chain << ""
      end
    end

    private def subscript_string_key(node : LibTreeSitter::TSNode, source : String) : String?
      seen_target = false
      Noir::TreeSitter.each_named_child(node) do |child|
        if !seen_target
          seen_target = true
          next
        end
        if Noir::TreeSitter.node_type(child) == "string"
          return decode_string(child, source)
        end
      end
      nil
    end

    # ---- shape helpers ----------------------------------------------

    private def first_named_child(node : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      count = LibTreeSitter.ts_node_named_child_count(node)
      return if count == 0
      LibTreeSitter.ts_node_named_child(node, 0_u32)
    end

    private def arguments_node(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(call) do |child|
        return child if Noir::TreeSitter.node_type(child) == "arguments"
      end
      nil
    end

    # tree-sitter-javascript wraps string contents in
    # `string_fragment` named children. Templates / escapes get
    # additional siblings — we just join the fragments which keeps
    # the simple-string case correct without choking on the rest.
    private def decode_string(node : LibTreeSitter::TSNode, source : String) : String
      buf = String.build do |io|
        Noir::TreeSitter.each_named_child(node) do |child|
          if Noir::TreeSitter.node_type(child) == "string_fragment"
            io << Noir::TreeSitter.node_text(child, source)
          end
        end
      end
      return buf unless buf.empty?
      raw = Noir::TreeSitter.node_text(node, source)
      if raw.size >= 2 && (raw[0] == '\'' || raw[0] == '"') && raw[0] == raw[-1]
        raw[1..-2]
      else
        raw
      end
    end
  end
end
