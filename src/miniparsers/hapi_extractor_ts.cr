require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./js_callee_extractor"
require "./js_ts_ast_helpers"

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
    include JSTSAstHelpers

    ANY_METHOD_VERBS = ["GET", "POST", "PUT", "DELETE", "PATCH"]

    HTTP_VERBS = Set{
      "GET", "POST", "PUT", "DELETE", "PATCH",
      "HEAD", "OPTIONS",
    }

    # `path:` is written as either a quoted string or a backtick template
    # literal — tree-sitter-javascript emits `template_string` for the
    # latter. `decode_string` has always known how to unwrap both; the
    # gate below rejecting backticks dropped the whole route object.
    STRING_LITERAL_TYPES = Set{"string", "template_string"}

    struct Route
      getter verb : String
      getter path : String
      getter line : Int32
      getter? has_body : Bool
      getter query_params : Array(String)
      getter header_params : Array(String)
      getter cookie_params : Array(String)
      getter callees : Array(JSCalleeExtractor::Entry)

      def initialize(@verb, @path, @line, @has_body,
                     @query_params, @header_params, @cookie_params,
                     @callees = [] of JSCalleeExtractor::Entry)
      end
    end

    # `module_exports`: the module's exported value is a route config too
    # (`module.exports = {...}`, `= [...]`, `= Helpers.withDefaults({...})`,
    # `export default {...}`), as in a haute-couture `routes/` module, which
    # haute-couture hands to `server.route()` itself.
    #
    # `references`: names handed to `server.route(name)` (or spread into its
    # array) that no declaration in this file binds, for the caller to
    # resolve through the file's imports and `extract_exported_routes`.
    def extract_routes(source : String, include_callees : Bool = false, module_exports : Bool = false, path : String = "", references : Array(String)? = nil) : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_js_family(source, path) do |root|
        decls = config_declarations(root, source)
        walk(root, source, routes, 0, include_callees, module_exports, decls, references)
      end
      routes
    end

    # The route config a module exports as `name` (`exports.name = [...]`,
    # `export const name`, `module.exports = { name }`), or its default
    # export when `name` is nil; another file passes it to `server.route()`.
    def extract_exported_routes(source : String, name : String?, include_callees : Bool = false, path : String = "") : Array(Route)
      routes = [] of Route
      Noir::TreeSitter.parse_js_family(source, path) do |root|
        decls = config_declarations(root, source)
        value = nil.as(LibTreeSitter::TSNode?)
        Noir::TreeSitter.each_named_child(root) do |stmt|
          stmt = Noir::TreeSitter.first_named_child(stmt) || next if Noir::TreeSitter.node_type(stmt) == "expression_statement"
          found = name ? named_export_value(stmt, source, name, decls) : exported_value(stmt, source)
          value = found if found
        end
        value.try { |v| emit_exported(v, source, routes, include_callees, decls, nil) }
      end
      routes
    end

    # Top-level and function-local `NAME = {...}` / `NAME = [...]` bindings,
    # first declaration wins.
    private def config_declarations(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      decls = Hash(String, LibTreeSitter::TSNode).new
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "variable_declarator"
        name = Noir::TreeSitter.field(node, "name") || next
        value = Noir::TreeSitter.field(node, "value") || next
        next unless Noir::TreeSitter.node_type(name) == "identifier"
        value = Noir::TreeSitter.unwrap_expression(value)
        next unless {"object", "array"}.includes?(Noir::TreeSitter.node_type(value))
        decls[Noir::TreeSitter.node_text(name, source)] ||= value
      end
      decls
    end

    private def named_export_value(stmt : LibTreeSitter::TSNode, source : String, name : String, decls : Hash(String, LibTreeSitter::TSNode)) : LibTreeSitter::TSNode?
      case Noir::TreeSitter.node_type(stmt)
      when "assignment_expression"
        left = Noir::TreeSitter.field(stmt, "left") || return
        right = Noir::TreeSitter.field(stmt, "right") || return
        left_text = Noir::TreeSitter.node_text(left, source)
        return right if left_text == "exports.#{name}" || left_text == "module.exports.#{name}"
        return unless left_text == "module.exports"
        right = Noir::TreeSitter.unwrap_expression(right)
        return unless Noir::TreeSitter.node_type(right) == "object"
        Noir::TreeSitter.each_named_child(right) do |entry|
          case Noir::TreeSitter.node_type(entry)
          when "shorthand_property_identifier"
            return decls[name]? if Noir::TreeSitter.node_text(entry, source) == name
          when "pair"
            key, value = pair_key_value(entry, source)
            return value if key == name
          end
        end
      when "export_statement"
        decl = Noir::TreeSitter.field(stmt, "declaration") || return
        Noir::TreeSitter.each_named_child(decl) do |declarator|
          next unless Noir::TreeSitter.node_type(declarator) == "variable_declarator"
          next unless Noir::TreeSitter.field(declarator, "name").try { |n| Noir::TreeSitter.node_text(n, source) } == name
          return Noir::TreeSitter.field(declarator, "value")
        end
      end
      nil
    end

    # ---- traversal --------------------------------------------------

    private def walk(node : LibTreeSitter::TSNode, source : String, routes : Array(Route), depth : Int32, include_callees : Bool, module_exports : Bool, decls : Hash(String, LibTreeSitter::TSNode), refs : Array(String)?)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "call_expression" && route_call?(node, source)
        emit_routes(node, source, routes, include_callees, decls, refs)
        return
      end
      # No early return: a plugin exported from `routes/` still registers
      # its own `server.route(...)` calls below.
      if module_exports && (exported = exported_value(node, source))
        emit_exported(exported, source, routes, include_callees, decls, refs)
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, source, routes, depth + 1, include_callees, module_exports, decls, refs)
      end
    end

    private def emit_exported(value : LibTreeSitter::TSNode, source : String, routes : Array(Route), include_callees : Bool, decls : Hash(String, LibTreeSitter::TSNode), refs : Array(String)?)
      if Noir::TreeSitter.node_type(value) == "call_expression"
        emit_routes(value, source, routes, include_callees, decls, refs)
      else
        emit_config(value, source, routes, include_callees, decls, refs)
      end
    end

    private def exported_value(node : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
      case Noir::TreeSitter.node_type(node)
      when "assignment_expression"
        left = Noir::TreeSitter.first_named_child(node) || return
        return unless Noir::TreeSitter.node_text(left, source) == "module.exports"
      when "export_statement"
        return unless Noir::TreeSitter.node_text(node, source).starts_with?("export default")
      else
        return
      end
      value = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.each_named_child(node) { |child| value = child }
      value.try { |v| Noir::TreeSitter.unwrap_expression(v) }
    end

    private def route_call?(call : LibTreeSitter::TSNode, source : String) : Bool
      callee = Noir::TreeSitter.first_named_child(call)
      return false unless callee
      return false unless Noir::TreeSitter.node_type(callee) == "member_expression"

      Noir::TreeSitter.each_named_child(callee) do |child|
        if Noir::TreeSitter.node_type(child) == "property_identifier"
          return Noir::TreeSitter.node_text(child, source) == "route"
        end
      end
      false
    end

    private def emit_routes(call : LibTreeSitter::TSNode, source : String, routes : Array(Route), include_callees : Bool, decls : Hash(String, LibTreeSitter::TSNode), refs : Array(String)?)
      args = arguments_node(call)
      return unless args

      Noir::TreeSitter.each_named_child(args) do |arg|
        emit_config(arg, source, routes, include_callees, decls, refs)
      end
    end

    # One route config object, or an array of them; a name or a spread
    # (`[...userRoutes, ...noteRoutes]`) stands for the config it binds.
    private def emit_config(node : LibTreeSitter::TSNode, source : String, routes : Array(Route), include_callees : Bool, decls : Hash(String, LibTreeSitter::TSNode), refs : Array(String)?, hops : Int32 = 0)
      node = Noir::TreeSitter.unwrap_expression(node)
      case Noir::TreeSitter.node_type(node)
      when "object"
        emit_route_object(node, source, routes, include_callees)
      when "array"
        Noir::TreeSitter.each_named_child(node) do |elem|
          elem = Noir::TreeSitter.unwrap_expression(elem)
          case Noir::TreeSitter.node_type(elem)
          when "object"
            emit_route_object(elem, source, routes, include_callees)
          when "identifier", "spread_element"
            emit_config(elem, source, routes, include_callees, decls, refs, hops)
          end
        end
      when "spread_element"
        Noir::TreeSitter.first_named_child(node).try { |inner| emit_config(inner, source, routes, include_callees, decls, refs, hops) }
      when "identifier"
        name = Noir::TreeSitter.node_text(node, source)
        if value = decls[name]?
          # A self-referencing spread (`const a = [...a]`) must terminate.
          emit_config(value, source, routes, include_callees, decls, refs, hops + 1) if hops < 4
        else
          refs.try { |r| r << name unless r.includes?(name) }
        end
      end
    end

    private def emit_route_object(obj : LibTreeSitter::TSNode, source : String, routes : Array(Route), include_callees : Bool)
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
          path = decode_string(value, source) if STRING_LITERAL_TYPES.includes?(Noir::TreeSitter.node_type(value))
        when "handler"
          handler = value
        when "options", "config"
          # `options: { auth, handler }`, the shape hapi 17+ documents.
          handler ||= nested_handler(value, source) if Noir::TreeSitter.node_type(value) == "object"
        end
      end

      resolved_path = path
      return if resolved_path.nil? || methods.empty?
      line = Noir::TreeSitter.node_start_row(obj)

      query_params = [] of String
      header_params = [] of String
      cookie_params = [] of String
      has_body = false
      callees = [] of JSCalleeExtractor::Entry

      if handler
        if receiver = handler_parameters(handler).first?.try { |param| parameter_name(param, source) }
          if body = Noir::TreeSitter.field(handler, "body")
            scan_handler(body, source, receiver, 0) do |kind, value|
              case kind
              when :query  then query_params << value
              when :header then header_params << value
              when :cookie then cookie_params << value
              when :body   then has_body = true
              end
            end
          end
        end
        callees = JSCalleeExtractor.callees_for_handler_node(handler, source, "") if include_callees
      end

      query_params.uniq!
      header_params.uniq!
      cookie_params.uniq!
      methods.each do |verb|
        routes << Route.new(verb, resolved_path, line, has_body,
          query_params, header_params, cookie_params, callees)
      end
    end

    private def nested_handler(obj : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(obj) do |pair|
        next unless Noir::TreeSitter.node_type(pair) == "pair"
        key, value = pair_key_value(pair, source)
        return value if key == "handler"
      end
      nil
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
          value = Noir::TreeSitter.unwrap_expression(child) if value.nil?
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
        Noir::TreeSitter.each_named_arg(value) do |elem|
          elem = Noir::TreeSitter.unwrap_expression(elem)
          if Noir::TreeSitter.node_type(elem) == "string"
            text = decode_string(elem, source).upcase
            sink << text if HTTP_VERBS.includes?(text)
          end
        end
      end
    end

    # ---- handler-body scan ------------------------------------------

    private def handler_parameters(handler : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
      params = [] of LibTreeSitter::TSNode
      if single = Noir::TreeSitter.field(handler, "parameter")
        params << single
      elsif formal = Noir::TreeSitter.field(handler, "parameters")
        Noir::TreeSitter.each_named_arg(formal) { |param| params << param }
      end
      params
    end

    private def parameter_name(param : LibTreeSitter::TSNode, source : String) : String?
      param = Noir::TreeSitter.field(param, "pattern") || param
      param = Noir::TreeSitter.field(param, "left") || param if Noir::TreeSitter.node_type(param) == "assignment_pattern"
      Noir::TreeSitter.node_text(param, source) if Noir::TreeSitter.node_type(param) == "identifier"
    end

    private def member_key(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "member_expression"
        Noir::TreeSitter.field(node, "property").try { |property| Noir::TreeSitter.node_text(property, source) }
      when "subscript_expression"
        subscript_string_key(node, source)
      end
    end

    # Exactly `req.query` (or `req['query']`), so a nested value's members
    # cannot become additional request keys.
    private def request_group(node : LibTreeSitter::TSNode, source : String, receiver : String) : String?
      node = Noir::TreeSitter.unwrap_expression(node)
      object = Noir::TreeSitter.field(node, "object").try { |value| Noir::TreeSitter.unwrap_expression(value) } || return
      return unless Noir::TreeSitter.node_type(object) == "identifier" && Noir::TreeSitter.node_text(object, source) == receiver
      member_key(node, source)
    end

    private def scan_handler(node : LibTreeSitter::TSNode, source : String, receiver : String, depth : Int32, &block : Symbol, String ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH
      ty = Noir::TreeSitter.node_type(node)
      case ty
      when "arrow_function", "function_expression", "function_declaration",
           "generator_function", "generator_function_declaration", "method_definition"
        return if handler_parameters(node).any? { |param| parameter_name(param, source) == receiver }
      end

      if ty == "member_expression" || ty == "subscript_expression"
        if key = member_key(node, source)
          object = Noir::TreeSitter.field(node, "object")
          group = object.try { |value| request_group(value, source, receiver) }
          case group
          when "query"   then block.call(:query, key)
          when "headers" then block.call(:header, key)
          when "state"   then block.call(:cookie, key)
          when "payload" then block.call(:body, "")
          end
        end
        block.call(:body, "") if request_group(node, source, receiver) == "payload"
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        scan_handler(child, source, receiver, depth + 1, &block)
      end
    end
  end
end
