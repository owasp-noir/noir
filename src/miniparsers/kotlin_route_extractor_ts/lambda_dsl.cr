# Part of Noir::TreeSitterKotlinRouteExtractor: the JVM "lambda DSL"
# routing style (Javalin) written in Kotlin:
#
#   app.get("/users/{id}") { ctx -> ctx.queryParam("q") }
#   app.post("/users", UserController::create)
#   config.router.apiBuilder { path("/api") { get("/x") { ctx -> } } }
#
# Kotlin twin of `TreeSitterJvmLambdaDslExtractor`: same `Config`, same
# `Route`, same receiver guard. The difference is the call shape — a
# trailing lambda makes `get("/x") { }` an outer `call_expression`
# wrapping the inner `get("/x")` call, which `lambda_dsl_call` folds back
# into one call.
#
# ponytail: handlers passed as a `Handler` variable or an `object :`
# expression are not resolved for params (the route itself is still
# emitted when the call has a receiver-less or lambda/reference shape).
module Noir
  module TreeSitterKotlinRouteExtractor
    private record LambdaDslCall,
      name : String,
      receiver : LibTreeSitter::TSNode?,
      args : Array(LibTreeSitter::TSNode),
      lambda : LibTreeSitter::TSNode?,
      type_args : LibTreeSitter::TSNode?

    def extract_lambda_dsl_routes(source : String,
                                  config : TreeSitterJvmLambdaDslExtractor::Config,
                                  constants : Hash(String, String)? = nil,
                                  *,
                                  include_callees : Bool = false) : Array(TreeSitterJvmLambdaDslExtractor::Route)
      routes = [] of TreeSitterJvmLambdaDslExtractor::Route
      constants ||= expand_constant_interpolations(extract_string_constants(source))
      Noir::TreeSitter.parse_kotlin(source) do |root|
        functions = Hash(String, LibTreeSitter::TSNode).new
        index_function_bodies(root, source, functions, "")
        walk_lambda_dsl(root, source, "", config, routes, constants, functions, 0, include_callees)
      end
      routes
    end

    private def walk_lambda_dsl(node : LibTreeSitter::TSNode,
                                source : String,
                                prefix : String,
                                config : TreeSitterJvmLambdaDslExtractor::Config,
                                routes : Array(TreeSitterJvmLambdaDslExtractor::Route),
                                constants : Hash(String, String),
                                functions : Hash(String, LibTreeSitter::TSNode),
                                depth : Int32,
                                include_callees : Bool)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "call_expression" && (call = lambda_dsl_call(node, source))
        name = call.name
        handled = true
        if verb = config.verb_methods[name]?
          emit_lambda_dsl_route(node, call, source, verb, prefix, config, routes, constants, functions, include_callees)
        elsif config.websocket_methods.includes?(name)
          emit_lambda_dsl_route(node, call, source, "GET", prefix, config, routes, constants, functions, include_callees, "ws")
        elsif config.handler_methods.includes?(name)
          # `addHandler(HandlerType.GET, "/x", handler)`
          verb = call.args.first?.try { |arg| Noir::TreeSitter.node_text(arg, source).match(/(?:HandlerType|HttpMethod)\.([A-Z]+)/).try(&.[1]) }
          emit_lambda_dsl_route(node, call, source, verb, prefix, config, routes, constants, functions, include_callees) if verb
        elsif config.crud_methods.includes?(name)
          emit_lambda_dsl_crud_routes(node, call, source, prefix, routes, constants)
        elsif config.nest_methods.includes?(name) || config.transparent_methods.includes?(name)
          new_prefix = prefix
          if config.nest_methods.includes?(name) && (path = lambda_dsl_string_argument(call, source, constants))
            new_prefix = Noir::URLPath.join_trimmed(prefix, path)
          end
          if body = lambda_dsl_handler_lambda(call)
            walk_lambda_dsl(body, source, new_prefix, config, routes, constants, functions, depth + 1, include_callees)
          end
        else
          handled = false
        end

        if handled
          # A fluent chain — `Javalin.create().get("/a") { }.post("/b") { }` —
          # keeps the earlier routes in the receiver.
          if receiver = call.receiver
            walk_lambda_dsl(receiver, source, prefix, config, routes, constants, functions, depth + 1, include_callees)
          end
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_lambda_dsl(child, source, prefix, config, routes, constants, functions, depth + 1, include_callees)
      end
    end

    private def emit_lambda_dsl_route(node : LibTreeSitter::TSNode,
                                      call : LambdaDslCall,
                                      source : String,
                                      verb : String,
                                      prefix : String,
                                      config : TreeSitterJvmLambdaDslExtractor::Config,
                                      routes : Array(TreeSitterJvmLambdaDslExtractor::Route),
                                      constants : Hash(String, String),
                                      functions : Hash(String, LibTreeSitter::TSNode),
                                      include_callees : Bool,
                                      protocol : String = "http")
      # A verb call is a route only with a handler or an allowlisted router
      # receiver — `map.put("k", "v")` must not become `PUT /k`. Unlike
      # Java, a bare call is no exception: Kotlin scope functions make
      # `buildJsonObject { put("status", "up") }` receiver-less.
      receiver = call.receiver
      return unless lambda_dsl_handler?(call) ||
                    (receiver && config.router_receivers.includes?(Noir::TreeSitter.node_text(receiver, source).split('.').last.strip))

      path = lambda_dsl_string_argument(call, source, constants)
      if path.nil?
        # Javalin's path-less `get(handler)` inside a `path("...")` block.
        return if prefix.empty? || !lambda_dsl_handler_first?(call)
        path = ""
      end

      query_params = [] of String
      form_params = [] of String
      header_params = [] of String
      cookie_params = [] of String
      body_type : String? = nil
      has_body = false
      callees = [] of Tuple(String, Int32)

      if body = lambda_dsl_handler_lambda(call) || lambda_dsl_referenced_body(call, source, functions)
        scan_lambda_dsl_handler(body, source, config, constants, 0) do |kind, value|
          case kind
          when :query  then query_params << value
          when :form   then form_params << value
          when :header then header_params << value
          when :cookie then cookie_params << value
          when :body   then has_body = true
          when :body_typed
            body_type = value
            has_body = true
          end
        end
        if include_callees
          Noir::KotlinCalleeExtractor.callees_in_lambda(body, source, "").each do |(name, _path, line)|
            callees << {name, line}
          end
        end
      end

      routes << TreeSitterJvmLambdaDslExtractor::Route.new(verb, Noir::URLPath.join_trimmed(prefix, path),
        Noir::TreeSitter.call_name_row(node), body_type, has_body,
        query_params.uniq, form_params.uniq, header_params.uniq, cookie_params.uniq, callees, protocol)
    end

    private def emit_lambda_dsl_crud_routes(node : LibTreeSitter::TSNode,
                                            call : LambdaDslCall,
                                            source : String,
                                            prefix : String,
                                            routes : Array(TreeSitterJvmLambdaDslExtractor::Route),
                                            constants : Hash(String, String))
      item_arg = lambda_dsl_string_argument(call, source, constants)
      return if item_arg.nil? && prefix.empty?

      item_path = item_arg ? Noir::URLPath.join_trimmed(prefix, item_arg) : prefix
      collection_path = TreeSitterJvmLambdaDslExtractor.crud_collection_path(item_path)
      line = Noir::TreeSitter.call_name_row(node)
      { {"GET", collection_path}, {"POST", collection_path}, {"GET", item_path},
       {"PATCH", item_path}, {"DELETE", item_path} }.each do |(verb, path)|
        routes << TreeSitterJvmLambdaDslExtractor::Route.new(verb, path, line, nil, false,
          [] of String, [] of String, [] of String, [] of String, [] of Tuple(String, Int32))
      end
    end

    private def scan_lambda_dsl_handler(node : LibTreeSitter::TSNode,
                                        source : String,
                                        config : TreeSitterJvmLambdaDslExtractor::Config,
                                        constants : Hash(String, String),
                                        depth : Int32,
                                        &block : Symbol, String ->)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      if Noir::TreeSitter.node_type(node) == "call_expression" && (call = lambda_dsl_call(node, source))
        name = call.name
        # A nested route is a sibling in its own right; the outer walk
        # reaches it.
        return if config.verb_methods.has_key?(name) && (lambda_dsl_handler?(call) || lambda_dsl_string_argument(call, source, constants))
        return if config.websocket_methods.includes?(name) || config.handler_methods.includes?(name) ||
                  config.nest_methods.includes?(name)

        # `header(name, value)` / `cookie(name, value)` are Javalin's
        # response setters; only the one-argument form reads the request.
        single = call.args.size == 1
        if config.query_methods.includes?(name)
          lambda_dsl_string_argument(call, source, constants).try { |value| block.call(:query, value) }
        elsif config.form_methods.includes?(name)
          lambda_dsl_string_argument(call, source, constants).try { |value| block.call(:form, value) }
        elsif config.header_methods.includes?(name)
          if name != "header" || single
            lambda_dsl_string_argument(call, source, constants).try { |value| block.call(:header, value) }
          end
        elsif config.cookie_methods.includes?(name)
          if name != "cookie" || single
            lambda_dsl_string_argument(call, source, constants).try { |value| block.call(:cookie, value) }
          end
        elsif config.body_typed_methods.includes?(name)
          block.call(:body_typed, lambda_dsl_body_type(call, source) || "")
        elsif config.body_methods.includes?(name)
          block.call(:body, "")
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        scan_lambda_dsl_handler(child, source, config, constants, depth + 1, &block)
      end
    end

    # Fold a Kotlin `call_expression` into name / receiver / value
    # arguments / trailing lambda. nil when the callee is not a plain or
    # `receiver.name` call.
    private def lambda_dsl_call(node : LibTreeSitter::TSNode, source : String) : LambdaDslCall?
      callee = Noir::TreeSitter.first_named_child(node)
      return unless callee

      args = [] of LibTreeSitter::TSNode
      lambda : LibTreeSitter::TSNode? = nil
      type_args : LibTreeSitter::TSNode? = nil
      has_value_args = false
      Noir::TreeSitter.each_named_child(node) do |suffix|
        next unless Noir::TreeSitter.node_type(suffix) == "call_suffix"
        Noir::TreeSitter.each_named_child(suffix) do |part|
          case Noir::TreeSitter.node_type(part)
          when "type_arguments" then type_args = part
          when "annotated_lambda"
            lambda = Noir::TreeSitter.first_named_child(part)
          when "value_arguments"
            has_value_args = true
            Noir::TreeSitter.each_named_child(part) do |arg|
              next unless Noir::TreeSitter.node_type(arg) == "value_argument"
              # `name = value` keeps the value, the argument's last child.
              value : LibTreeSitter::TSNode? = nil
              Noir::TreeSitter.each_named_child(arg) { |child| value = child }
              value.try { |v| args << v }
            end
          end
        end
      end

      case Noir::TreeSitter.node_type(callee)
      when "simple_identifier"
        LambdaDslCall.new(Noir::TreeSitter.node_text(callee, source), nil, args, lambda, type_args)
      when "navigation_expression"
        name = ""
        receiver : LibTreeSitter::TSNode? = nil
        Noir::TreeSitter.each_named_child(callee) do |part|
          if Noir::TreeSitter.node_type(part) == "navigation_suffix"
            Noir::TreeSitter.each_named_child(part) do |id|
              name = Noir::TreeSitter.node_text(id, source) if Noir::TreeSitter.node_type(id) == "simple_identifier"
            end
          else
            receiver = part
          end
        end
        LambdaDslCall.new(name, receiver, args, lambda, type_args) unless name.empty?
      when "call_expression"
        # `get("/x") { ... }`: the trailing lambda wraps the inner call.
        return if has_value_args || lambda.nil?
        inner = lambda_dsl_call(callee, source)
        return unless inner && inner.lambda.nil?
        LambdaDslCall.new(inner.name, inner.receiver, inner.args, lambda, inner.type_args || type_args)
      end
    end

    private def lambda_dsl_string_argument(call : LambdaDslCall,
                                           source : String,
                                           constants : Hash(String, String)) : String?
      call.args.each do |arg|
        if value = resolve_string_value(arg, source, constants, constants)
          return value
        end
      end
      nil
    end

    private def lambda_dsl_handler_arg?(arg : LibTreeSitter::TSNode) : Bool
      {"lambda_literal", "annotated_lambda", "callable_reference", "anonymous_function"}.includes?(Noir::TreeSitter.node_type(arg))
    end

    private def lambda_dsl_handler?(call : LambdaDslCall) : Bool
      !call.lambda.nil? || call.args.any? { |arg| lambda_dsl_handler_arg?(arg) }
    end

    private def lambda_dsl_handler_first?(call : LambdaDslCall) : Bool
      if first = call.args.first?
        lambda_dsl_handler_arg?(first)
      else
        !call.lambda.nil?
      end
    end

    private def lambda_dsl_handler_lambda(call : LambdaDslCall) : LibTreeSitter::TSNode?
      call.lambda || call.args.find { |arg| Noir::TreeSitter.node_type(arg) == "lambda_literal" }
    end

    # `UserController::create` / `::create` → the body of the same-file
    # `fun create(...)` declared in `UserController` / at the top level.
    private def lambda_dsl_referenced_body(call : LambdaDslCall,
                                           source : String,
                                           functions : Hash(String, LibTreeSitter::TSNode)) : LibTreeSitter::TSNode?
      call.args.each do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "callable_reference"
        owner = ""
        name = ""
        Noir::TreeSitter.each_named_child(arg) do |part|
          case Noir::TreeSitter.node_type(part)
          when "type_identifier"   then owner = Noir::TreeSitter.node_text(part, source)
          when "simple_identifier" then name = Noir::TreeSitter.node_text(part, source)
          end
        end
        if body = functions[owner.empty? ? name : "#{owner}.#{name}"]?
          return body
        end
      end
      nil
    end

    # `ctx.bodyAsClass<User>()` or `ctx.bodyAsClass(User::class.java)`.
    private def lambda_dsl_body_type(call : LambdaDslCall, source : String) : String?
      if type_args = call.type_args
        name = resource_type_name(Noir::TreeSitter.first_named_child(type_args), source)
        return name unless name.empty?
      end
      call.args.each do |arg|
        text = Noir::TreeSitter.node_text(arg, source)
        if match = text.match(/\A([A-Za-z_][A-Za-z0-9_.]*)::class\b/)
          return match[1].split('.').last
        end
      end
      nil
    end

    # Function bodies keyed `Owner.name` (or `name` at the top level), so
    # `BookController::create` never resolves to `UserController.create`.
    private def index_function_bodies(node : LibTreeSitter::TSNode,
                                      source : String,
                                      functions : Hash(String, LibTreeSitter::TSNode),
                                      owner : String,
                                      depth : Int32 = 0)
      return if depth > Noir::TreeSitter::MAX_AST_DEPTH

      case Noir::TreeSitter.node_type(node)
      when "function_declaration"
        Noir::TreeSitter.each_named_child(node) do |child|
          next unless Noir::TreeSitter.node_type(child) == "function_body"
          name = function_name(node, source)
          functions[owner.empty? ? name : "#{owner}.#{name}"] ||= child
        end
        return
      when "class_declaration", "object_declaration"
        owner = type_identifier_text(node, source)
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        index_function_bodies(child, source, functions, owner, depth + 1)
      end
    end
  end
end
