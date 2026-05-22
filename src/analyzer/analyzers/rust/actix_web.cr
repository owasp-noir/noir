require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # actix-web analyzer (tree-sitter port). actix-web wires routes via
  # `#[get("/path")]` / `#[post(...)]` attribute macros that sit as
  # **siblings** of the `function_item` they decorate (this is how
  # tree-sitter-rust models outer attributes — they aren't children of
  # the item they attach to). The analyzer walks every container and
  # pairs each routing attribute with the function_item that follows
  # it, skipping intermediate attribute_items and doc comments.
  class ActixWeb < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        scoped_services = collect_service_registrations(root, source, test_regions)

        each_routing_pair(root) do |attr, function|
          next if RustEngine.inside_test_region?(attr, test_regions)

          route = extract_route(attr, source)
          next unless route
          route_path, method, attr_row = route

          handler_name = function_name(function, source)
          prefixes = handler_name ? scoped_services[handler_name]? : nil

          if prefixes && !prefixes.empty?
            prefixes.each do |prefix|
              endpoint_path = scoped_route_path(prefix, route_path)
              endpoints << build_attribute_endpoint(endpoint_path, method, attr_row, path, function, source, include_callee)
            end
          else
            endpoints << build_attribute_endpoint(route_path, method, attr_row, path, function, source, include_callee)
          end
        end

        # Second pass: `App::new().route("/path", web::<verb>().to(handler))`
        # and `web::resource("/path").route(web::<verb>().to(handler))`
        # registrations. The attribute walk above only catches the
        # `#[get(...)]` macro form, so manual builder-style routes
        # were silently dropped.
        walk_calls(root) do |call|
          next if RustEngine.inside_test_region?(call, test_regions)

          builder_route = extract_builder_route(call, source)
          next unless builder_route
          route_path, methods = builder_route
          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(call) + 1))
          methods.each do |verb|
            endpoint = Endpoint.new(route_path, verb, details)
            extract_path_params(route_path, endpoint)
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    private def build_attribute_endpoint(route_path : String,
                                         method : String,
                                         attr_row : Int32,
                                         file_path : String,
                                         function : LibTreeSitter::TSNode,
                                         source : String,
                                         include_callee : Bool) : Endpoint
      details = Details.new(PathInfo.new(file_path, attr_row))
      endpoint = Endpoint.new(route_path, method, details)

      extract_path_params(route_path, endpoint)
      extract_function_params(function, source, endpoint)
      attach_handler_callees(function, source, file_path, endpoint) if include_callee

      endpoint
    end

    # Actix attribute routes are commonly mounted with
    # `web::scope("/api").service(handler)`. The attribute itself only
    # carries the local path, so the service registration is needed to
    # avoid emitting `/posts` when the real endpoint is `/api/posts`.
    private def collect_service_registrations(root : LibTreeSitter::TSNode,
                                              source : String,
                                              test_regions : Array(Tuple(Int32, Int32))) : Hash(String, Array(String))
      registrations = {} of String => Array(String)
      collect_service_registrations(root, source, test_regions, "", registrations)
      registrations
    end

    private def collect_service_registrations(node : LibTreeSitter::TSNode,
                                              source : String,
                                              test_regions : Array(Tuple(Int32, Int32)),
                                              active_prefix : String,
                                              registrations : Hash(String, Array(String)))
      if Noir::TreeSitter.node_type(node) == "call_expression"
        return if RustEngine.inside_test_region?(node, test_regions)

        if field_call_name(node, source) == "service"
          args = Noir::TreeSitter.field(node, "arguments")
          return unless args
          named = named_children(args)
          return unless named.size == 1

          function = Noir::TreeSitter.field(node, "function")
          return unless function
          receiver = Noir::TreeSitter.field(function, "value")
          receiver_prefix = receiver ? (extract_scope_prefix(receiver, source) || "") : ""
          service_prefix = scoped_route_path(active_prefix, receiver_prefix)

          if handler_name = service_handler_name(named[0], source)
            push_registration(registrations, handler_name, service_prefix)
          else
            collect_service_registrations(named[0], source, test_regions, service_prefix, registrations)
          end

          collect_service_registrations(receiver, source, test_regions, active_prefix, registrations) if receiver
          return
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        collect_service_registrations(child, source, test_regions, active_prefix, registrations)
      end
    end

    private def push_registration(registrations : Hash(String, Array(String)),
                                  handler_name : String,
                                  prefix : String)
      prefixes = registrations[handler_name] ||= [] of String
      prefixes << prefix unless prefixes.includes?(prefix)
    end

    private def service_handler_name(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "identifier"
        Noir::TreeSitter.node_text(node, source)
      when "scoped_identifier"
        Noir::TreeSitter.node_text(node, source).split("::").last
      end
    end

    private def function_name(function : LibTreeSitter::TSNode, source : String) : String?
      name = Noir::TreeSitter.field(function, "name")
      name ? Noir::TreeSitter.node_text(name, source) : nil
    end

    # Walks `call_expression` nodes whose receiver chain looks like
    # `<owner>.route(<path_lit>, web::<verb>().to(<handler>))` (i.e.,
    # `App::new().route(...)`, `web::scope("/x").route(...)`,
    # `web::resource("/y").route(...)`) and returns
    # `{path, [verbs]}`. Returns `nil` when the shape doesn't match.
    private def extract_builder_route(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(String))?
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "field_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      return unless Noir::TreeSitter.node_text(field, source) == "route"

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(args) { |c| named << c }
      return if named.empty?

      # Two argument shapes:
      #   1. `.route("/path", web::verb().to(handler))` — path is
      #      positional[0], verb-call is positional[1].
      #   2. `.route(web::verb().to(handler))` (resource builder) —
      #      path is on the parent `web::resource("/x")` call which
      #      sits as the receiver of this field_expression.
      if named.size == 1
        receiver = Noir::TreeSitter.field(function, "value")
        return unless receiver
        path_lit = extract_resource_path(receiver, source)
        return unless path_lit
        methods = extract_web_verbs(named[0], source)
        return if methods.empty?
        if scope_prefix = extract_scope_prefix(receiver, source)
          path_lit = scoped_route_path(scope_prefix, path_lit)
        end
        return {path_lit, methods}
      end

      path_lit = first_string_literal_text(named[0], source)
      return unless path_lit

      methods = extract_web_verbs(named[1], source)
      return if methods.empty?

      # If the receiver chain contains a `web::scope("/x")` call,
      # prepend that prefix to the route path. Same idea as Axum's
      # `.nest(...)` (still out of scope here) but easier because
      # actix puts scope and route on the same builder chain.
      receiver = Noir::TreeSitter.field(function, "value")
      if receiver
        scope_prefix = extract_scope_prefix(receiver, source)
        if scope_prefix
          path_lit = scoped_route_path(scope_prefix, path_lit)
        end
      end

      {path_lit, methods}
    end

    # Walks the receiver chain looking for the nearest enclosing
    # `web::scope("/x")` call and returns its path argument.
    private def extract_scope_prefix(node : LibTreeSitter::TSNode, source : String) : String?
      cursor = node
      while Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn = Noir::TreeSitter.field(cursor, "function")
        return unless fn
        case Noir::TreeSitter.node_type(fn)
        when "scoped_identifier"
          text = Noir::TreeSitter.node_text(fn, source)
          if text.ends_with?("::scope")
            args = Noir::TreeSitter.field(cursor, "arguments")
            return unless args
            named = [] of LibTreeSitter::TSNode
            Noir::TreeSitter.each_named_child(args) { |c| named << c }
            return if named.empty?
            return first_string_literal_text(named[0], source)
          end
          return
        when "field_expression"
          inner = Noir::TreeSitter.field(fn, "value")
          return unless inner
          cursor = inner
        else
          return
        end
      end
      nil
    end

    private def field_call_name(call : LibTreeSitter::TSNode, source : String) : String?
      function = Noir::TreeSitter.field(call, "function")
      return unless function && Noir::TreeSitter.node_type(function) == "field_expression"
      field = Noir::TreeSitter.field(function, "field")
      field ? Noir::TreeSitter.node_text(field, source) : nil
    end

    private def named_children(node : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      named
    end

    private def scoped_route_path(prefix : String, route_path : String) : String
      normalized_prefix = prefix.starts_with?("/") ? prefix : "/#{prefix}"
      normalized_path = route_path.starts_with?("/") ? route_path : "/#{route_path}"

      return normalized_path if normalized_prefix == "/"
      clean_prefix = normalized_prefix.rstrip('/')
      return normalized_path if normalized_path == clean_prefix || normalized_path.starts_with?("#{clean_prefix}/")

      suffix = normalized_path.lstrip('/')
      return clean_prefix if suffix.empty?

      "#{clean_prefix}/#{suffix}"
    end

    # Find the path string carried by a `web::resource(<path>)` call.
    # Walks downward in case the receiver itself is a chain of method
    # calls layered on top of the resource builder (e.g.
    # `web::resource("/x").guard(...)`).
    private def extract_resource_path(node : LibTreeSitter::TSNode, source : String) : String?
      cursor = node
      while Noir::TreeSitter.node_type(cursor) == "call_expression"
        fn = Noir::TreeSitter.field(cursor, "function")
        return unless fn
        case Noir::TreeSitter.node_type(fn)
        when "scoped_identifier"
          text = Noir::TreeSitter.node_text(fn, source)
          return unless text.ends_with?("::resource")
          args = Noir::TreeSitter.field(cursor, "arguments")
          return unless args
          named = [] of LibTreeSitter::TSNode
          Noir::TreeSitter.each_named_child(args) { |c| named << c }
          return if named.empty?
          return first_string_literal_text(named[0], source)
        when "field_expression"
          inner = Noir::TreeSitter.field(fn, "value")
          return unless inner
          cursor = inner
        else
          return
        end
      end
      nil
    end

    # Pulls every `web::<verb>()` call from a chain like
    # `web::get().to(handler)` or
    # `web::get().or(web::post()).to(handler)`. Walks downward
    # through `call_expression` / `field_expression` until exhausted.
    private def extract_web_verbs(node : LibTreeSitter::TSNode, source : String) : Array(String)
      verbs = [] of String
      walk_calls(node) do |call|
        function = Noir::TreeSitter.field(call, "function")
        next unless function
        # `web::get()` is a `call_expression` whose function is a
        # `scoped_identifier` ending in a verb.
        if Noir::TreeSitter.node_type(function) == "scoped_identifier"
          text = Noir::TreeSitter.node_text(function, source)
          if (last = text.split("::").last?) && HTTP_VERBS.includes?(last)
            verbs << last.upcase
          end
        end
      end
      verbs.uniq
    end

    private def walk_calls(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node) if Noir::TreeSitter.node_type(node) == "call_expression"
      Noir::TreeSitter.each_named_child(node) do |child|
        walk_calls(child, &block)
      end
    end

    # `#[get("/x")]` → `{"/x", "GET", attr_row_1based}`. Returns `nil`
    # for non-routing attributes (`#[derive(...)]`, `#[tokio::main]`,
    # …) so the iterator just skips past them.
    private def extract_route(attr_item : LibTreeSitter::TSNode,
                              source : String) : Tuple(String, String, Int32)?
      attr = find_named_child(attr_item, "attribute")
      return unless attr

      # tree-sitter-rust models the attribute path as the attribute's
      # required positional named child (identifier / scoped_identifier
      # / self / super / crate / metavariable). There is no `path:`
      # field — the named fields are `arguments` (the `(...)` token
      # tree) and `value` (for `#[key = expr]` shapes).
      verb = nil.as(String?)
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          verb = Noir::TreeSitter.node_text(child, source).downcase
          break
        end
      end
      return unless verb
      return unless HTTP_VERBS.includes?(verb)

      arguments = Noir::TreeSitter.field(attr, "arguments")
      route_path = first_string_literal_text(arguments, source)
      return unless route_path
      {route_path, verb.upcase, Noir::TreeSitter.node_start_row(attr_item) + 1}
    end

    # Path params like `/users/{id}`.
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # Walk the function's `parameters` once and tag the endpoint with
    # whichever extractor types appear. Each parameter's *text* is
    # examined as a single slice — equivalent to the per-line scan in
    # the legacy analyzer, bounded to the parameter list and free of
    # comment / string-literal false positives.
    def extract_function_params(function : LibTreeSitter::TSNode,
                                source : String,
                                endpoint : Endpoint)
      params_node = Noir::TreeSitter.field(function, "parameters")
      if params_node
        Noir::TreeSitter.each_named_child(params_node) do |param|
          text = Noir::TreeSitter.node_text(param, source)
          if text.includes?("web::Query<") || text.includes?(": web::Query")
            endpoint.push_param(Param.new("query", "", "query"))
          end
          if text.includes?("web::Json<") || text.includes?(": web::Json")
            endpoint.push_param(Param.new("body", "", "json"))
          end
          if text.includes?("web::Form<") || text.includes?(": web::Form")
            endpoint.push_param(Param.new("form", "", "form"))
          end
        end
      end

      body_node = Noir::TreeSitter.field(function, "body")
      return unless body_node
      collect_header_and_cookie_params(body_node, source, endpoint)
    end

    # Scan the body for `req.headers().get("X")` / `req.cookie("X")`
    # — the legacy regex pass, now bounded to `call_expression`
    # function texts so we don't false-positive on comments or string
    # literals containing the same substring.
    private def collect_header_and_cookie_params(body : LibTreeSitter::TSNode,
                                                 source : String,
                                                 endpoint : Endpoint)
      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        fn_text = call_function_text(call, source)
        next if fn_text.nil?

        if fn_text.ends_with?(".headers().get")
          first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source).try do |name|
            endpoint.push_param(Param.new(name, "", "header"))
          end
        elsif fn_text.ends_with?(".cookie")
          first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source).try do |name|
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        end
      end
    end

    private def attach_handler_callees(function : LibTreeSitter::TSNode,
                                       source : String,
                                       path : String,
                                       endpoint : Endpoint)
      body = Noir::TreeSitter.field(function, "body")
      return unless body
      entries = Noir::RustCalleeExtractorTS.callees_in_body(body, source, path)
      attach_rust_callees(endpoint, entries)
    end

    private def call_function_text(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node
      Noir::TreeSitter.node_text(fn_node, source)
    end

    # Walk `node`'s children at every depth and yield `(attribute_item,
    # function_item)` pairs where the attribute immediately precedes
    # the function (skipping intermediate attribute_items and doc
    # comments). This matches how `#[get(...)] async fn handler` is
    # laid out in the AST — both are top-level siblings, not parent /
    # child.
    private def each_routing_pair(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode, LibTreeSitter::TSNode ->)
      named = [] of LibTreeSitter::TSNode
      Noir::TreeSitter.each_named_child(node) { |c| named << c }
      named.each_with_index do |child, idx|
        if Noir::TreeSitter.node_type(child) == "attribute_item"
          pair_function = find_paired_function(named, idx + 1)
          block.call(child, pair_function) if pair_function
        end
        each_routing_pair(child, &block)
      end
    end

    private def find_paired_function(named : Array(LibTreeSitter::TSNode), start : Int32) : LibTreeSitter::TSNode?
      (start...named.size).each do |i|
        next_node = named[i]
        case Noir::TreeSitter.node_type(next_node)
        when "function_item"
          return next_node
        when "attribute_item", "line_comment", "block_comment"
          next
        else
          return # routing attributes only decorate functions
        end
      end
      nil
    end

    private def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      result : String? = nil
      walk(node) do |child|
        next if result
        next unless Noir::TreeSitter.node_type(child) == "string_literal"
        Noir::TreeSitter.each_named_child(child) do |grand|
          if Noir::TreeSitter.node_type(grand) == "string_content"
            result = Noir::TreeSitter.node_text(grand, source)
            break
          end
        end
      end
      result
    end

    private def find_named_child(node : LibTreeSitter::TSNode, type : String) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(node) do |child|
        return child if Noir::TreeSitter.node_type(child) == type
      end
      nil
    end

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end
  end
end
