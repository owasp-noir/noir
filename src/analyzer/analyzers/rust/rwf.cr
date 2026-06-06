require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # RWF analyzer (tree-sitter port). RWF registers routes in a handful
  # of shapes, all handled here:
  #
  #   route!("/path" => Controller)   single route; the controller's
  #                                   `Controller` impl `handle` body
  #                                   enumerates verbs + params.
  #   crud!("/path"  => Controller)   six RESTful routes (the
  #   rest!("/path"  => Controller)   RestController/ModelController
  #                                   convention).
  #   Controller.route("/path")       the same three as method calls
  #   Controller::new().rest("/p")    (no macro), plus
  #   controller.wildcard("/path")    a catch-all mount.
  #
  # Registrations almost always sit inside `Server::new(vec![ ... ])` /
  # `Engine::new(vec![ ... ])`. tree-sitter leaves a `vec!` body as a
  # flat `token_tree` with no `macro_invocation` / `call_expression`
  # nodes, so we re-parse each route-bearing macro body as an expression
  # fragment and scan it too, mapping line numbers back onto the file.
  class Rwf < RustEngine
    HTTP_METHODS = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]
    # `crud!` / `rest!` register the standard REST surface. `:id` is the
    # resource identifier param RWF uses for the member routes.
    REST_ROUTES = [
      {"", "GET"},        # list
      {"", "POST"},       # create
      {"/:id", "GET"},    # get
      {"/:id", "PUT"},    # update
      {"/:id", "PATCH"},  # patch
      {"/:id", "DELETE"}, # delete
    ]

    # A discovered route registration before it is expanded into
    # endpoints. `controller` is the controller/type name (used to find
    # the `handle` body for `:route`); it may be nil for anonymous
    # receivers.
    record Registration,
      path : String,
      controller : String?,
      kind : Symbol,
      row : Int32

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      @current_source = source
      Noir::TreeSitter.parse_rust(source) do |root|
        controller_bodies = collect_controller_handle_bodies(root, source)
        engine_prefixes = collect_engine_prefix_ranges(root, source)

        collect_registrations(root, source, engine_prefixes).each do |reg|
          case reg.kind
          when :engine
            # `engine!("/prefix" => engine)` mounts a sub-engine; it is
            # not itself an endpoint. Its child routes are prefix-composed
            # via `engine_prefixes` during fragment scanning, so emitting
            # the mount path here would be a phantom route.
            next
          when :route, :wildcard
            body = reg.controller ? controller_bodies[reg.controller]? : nil
            methods = body ? extract_methods(body, source) : [] of String
            methods << "GET" if methods.empty?

            details = Details.new(PathInfo.new(path, reg.row))
            methods.each do |http_method|
              endpoint = Endpoint.new(reg.path, http_method, details)
              extract_path_params(reg.path, endpoint)
              if body
                extract_controller_params(body, source, endpoint)
                if include_callee
                  entries = Noir::RustCalleeExtractorTS.callees_in_body(body, source, path)
                  attach_rust_callees(endpoint, entries)
                end
              end
              endpoints << endpoint
            end
          when :crud, :rest
            REST_ROUTES.each do |suffix, http_method|
              route_path = "#{reg.path.rstrip('/')}#{suffix}"
              # Root-mounted collection routes: "/".rstrip('/') + "" == "" — emit
              # "/" rather than an invalid empty URL.
              route_path = "/" if route_path.empty?
              details = Details.new(PathInfo.new(path, reg.row))
              endpoint = Endpoint.new(route_path, http_method, details)
              extract_path_params(route_path, endpoint)
              endpoints << endpoint
            end
          end
        end
      end

      endpoints
    end

    # Stashed during `analyze_file` so the nested traversal helpers
    # don't need to thread `source` through every recursion.
    @current_source : String = ""

    # Collect every route registration reachable from `root`: macros and
    # method calls in the real AST, plus everything hidden inside
    # re-parsed `vec!`-style macro bodies.
    private def collect_registrations(root : LibTreeSitter::TSNode,
                                      source : String,
                                      engine_prefixes : Array(Tuple(Int32, Int32, String))) : Array(Registration)
      sink = [] of Registration
      scan_registrations(root, source, 0, sink, "")

      collect_route_macro_fragments(root, source, engine_prefixes).each do |fragment, row_offset, prefix|
        Noir::TreeSitter.parse_rust(fragment) do |frag_root|
          scan_registrations(frag_root, fragment, row_offset, sink, prefix)
        end
      end

      sink
    end

    # Map each mounted sub-engine's `Engine::new(...)` byte range to its
    # mount prefix, so route registrations hidden in that engine's `vec!`
    # body inherit the prefix. `engine!("/admin" => engine)` is matched
    # textually (the macro body is an unparsed token tree); the matching
    # `let engine = Engine::new(...)` binding supplies the range.
    private def collect_engine_prefix_ranges(root : LibTreeSitter::TSNode, source : String) : Array(Tuple(Int32, Int32, String))
      mounts = {} of String => String
      source.scan(/engine!\s*\(\s*"([^"]*)"\s*=>\s*([A-Za-z_]\w*)\s*\)/) do |m|
        mounts[m[2]] = m[1]
      end
      ranges = [] of Tuple(Int32, Int32, String)
      return ranges if mounts.empty?
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "let_declaration"
        pattern = Noir::TreeSitter.field(node, "pattern")
        next unless pattern && Noir::TreeSitter.node_type(pattern) == "identifier"
        prefix = mounts[Noir::TreeSitter.node_text(pattern, source)]?
        next unless prefix
        value = Noir::TreeSitter.field(node, "value")
        next unless value
        ranges << {LibTreeSitter.ts_node_start_byte(value).to_i, LibTreeSitter.ts_node_end_byte(value).to_i, prefix}
      end
      ranges
    end

    private def join_engine_path(prefix : String, route_path : String) : String
      return route_path if prefix.empty?
      "/#{prefix.strip('/')}/#{route_path.lstrip('/')}".rstrip('/')
    end

    # Walk `node` for both registration shapes:
    #   * `route!`/`crud!`/`rest!`/`engine!` macro invocations, and
    #   * `.route(...)`/`.crud(...)`/`.rest(...)`/`.wildcard(...)` method
    #     calls.
    private def scan_registrations(node : LibTreeSitter::TSNode,
                                   source : String,
                                   row_offset : Int32,
                                   sink : Array(Registration),
                                   prefix : String)
      walk(node) do |child|
        case Noir::TreeSitter.node_type(child)
        when "macro_invocation"
          name_node = Noir::TreeSitter.field(child, "macro")
          next unless name_node
          kind = macro_kind(Noir::TreeSitter.node_text(name_node, source))
          next unless kind
          tokens = nil.as(LibTreeSitter::TSNode?)
          Noir::TreeSitter.each_named_child(child) do |c|
            tokens = c if Noir::TreeSitter.node_type(c) == "token_tree"
          end
          next unless tt = tokens
          decoded = decode_macro_token_tree(tt, source)
          next unless decoded
          route_path, controller = decoded
          # Prefix the route with its enclosing engine's mount path
          # (empty for top-level routes); `:engine` mounts keep their own
          # path since they are dropped at emit time.
          route_path = join_engine_path(prefix, route_path) if kind != :engine
          sink << Registration.new(route_path, controller, kind, Noir::TreeSitter.node_start_row(child) + 1 + row_offset)
        when "call_expression"
          reg = decode_method_call(child, source, row_offset)
          if reg
            reg = Registration.new(join_engine_path(prefix, reg.path), reg.controller, reg.kind, reg.row) unless prefix.empty?
            sink << reg
          end
        end
      end
    end

    private def macro_kind(name : String) : Symbol?
      case name
      when "route"  then :route
      when "crud"   then :crud
      when "rest"   then :rest
      when "engine" then :engine
      end
    end

    # `Controller.route("/path")` / `Controller::new().rest("/p")` /
    # `controller.wildcard("/p")`. The verb method names the registration
    # kind; the string argument is the path; the receiver names the
    # controller (best effort, used only to resolve a `handle` body).
    private def decode_method_call(call : LibTreeSitter::TSNode, source : String, row_offset : Int32) : Registration?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field
      kind =
        case Noir::TreeSitter.node_text(field, source)
        when "route"    then :route
        when "crud"     then :crud
        when "rest"     then :rest
        when "wildcard" then :wildcard
        else                 return
        end

      route_path = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
      return unless route_path

      receiver = Noir::TreeSitter.field(fn_node, "value")
      controller = receiver ? receiver_controller_name(receiver, source) : nil
      Registration.new(route_path, controller, kind, Noir::TreeSitter.node_start_row(call) + 1 + row_offset)
    end

    # First identifier-ish token of a method-call receiver, used as the
    # controller name. `IndexController` → `IndexController`,
    # `BasicAuthController::new()` → `BasicAuthController`.
    private def receiver_controller_name(receiver : LibTreeSitter::TSNode, source : String) : String?
      result : String? = nil
      walk(receiver) do |node|
        next if result
        case Noir::TreeSitter.node_type(node)
        when "identifier", "type_identifier"
          result = Noir::TreeSitter.node_text(node, source)
        when "scoped_identifier"
          result = Noir::TreeSitter.node_text(node, source).split("::").first
        end
      end
      result
    end

    # The token_tree inside `route!("/path" => Controller)`: the first
    # string literal is the path; the controller is the trailing
    # identifier so a scoped `controllers::login` resolves to `login`
    # (the controller type) rather than the module prefix.
    private def decode_macro_token_tree(tokens : LibTreeSitter::TSNode, source : String) : Tuple(String, String?)?
      route_path : String? = nil
      controller : String? = nil
      Noir::TreeSitter.each_named_child(tokens) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_literal"
          if route_path.nil?
            Noir::TreeSitter.each_named_child(child) do |grand|
              if Noir::TreeSitter.node_type(grand) == "string_content"
                route_path = Noir::TreeSitter.node_text(grand, source)
                break
              end
            end
          end
        when "identifier", "type_identifier"
          controller = Noir::TreeSitter.node_text(child, source)
        when "scoped_identifier"
          controller = Noir::TreeSitter.node_text(child, source).split("::").last
        end
      end
      rp = route_path
      return unless rp
      {rp, controller}
    end

    # Re-parseable expression fragments for every macro body that
    # mentions a route registration, paired with the 0-based row of the
    # macro's `token_tree` so detected routes map back to the file line.
    private def collect_route_macro_fragments(root : LibTreeSitter::TSNode,
                                              source : String,
                                              engine_prefixes : Array(Tuple(Int32, Int32, String))) : Array(Tuple(String, Int32, String))
      fragments = [] of Tuple(String, Int32, String)
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "macro_invocation"
        name_node = Noir::TreeSitter.field(node, "macro")
        # Skip the macros we decode directly; only re-parse container
        # macros (`vec!`, …) whose bodies hide registrations.
        next if name_node && macro_kind(Noir::TreeSitter.node_text(name_node, source))
        token_tree = nil.as(LibTreeSitter::TSNode?)
        Noir::TreeSitter.each_named_child(node) do |child|
          token_tree = child if Noir::TreeSitter.node_type(child) == "token_tree"
        end
        next unless tt = token_tree
        text = Noir::TreeSitter.node_text(tt, source)
        next unless text.includes?("route") || text.includes?("crud") || text.includes?("rest") || text.includes?("wildcard")
        # A `vec!` body sitting inside a mounted engine's `Engine::new(...)`
        # inherits that engine's mount prefix.
        tt_byte = LibTreeSitter.ts_node_start_byte(tt).to_i
        prefix = (engine_prefixes.find { |s, e, _| tt_byte >= s && tt_byte < e }).try(&.[2]) || ""
        fragments << {"fn __noir_rwf_wf() { let __noir_x = #{text}; }", Noir::TreeSitter.node_start_row(tt), prefix}
      end
      fragments
    end

    # Walk all `impl_item` nodes whose trait is `Controller` and store
    # the controller (impl target) → `handle` method's body node.
    private def collect_controller_handle_bodies(root : LibTreeSitter::TSNode,
                                                 source : String) : Hash(String, LibTreeSitter::TSNode)
      result = {} of String => LibTreeSitter::TSNode
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "impl_item"
        trait_node = Noir::TreeSitter.field(node, "trait")
        next unless trait_node
        trait_name = Noir::TreeSitter.node_text(trait_node, source).split("::").last
        next unless trait_name == "Controller"

        type_node = Noir::TreeSitter.field(node, "type")
        next unless type_node
        controller_name = Noir::TreeSitter.node_text(type_node, source)

        body_block = Noir::TreeSitter.field(node, "body")
        next unless body_block
        Noir::TreeSitter.each_named_child(body_block) do |member|
          next unless Noir::TreeSitter.node_type(member) == "function_item"
          name_node = Noir::TreeSitter.field(member, "name")
          next unless name_node
          next unless Noir::TreeSitter.node_text(name_node, source) == "handle"
          if handle_body = Noir::TreeSitter.field(member, "body")
            result[controller_name] = handle_body
          end
        end
      end
      result
    end

    # Walk the handle body for `Method::GET` etc. references via
    # `scoped_identifier` nodes. Mirrors the legacy `Method::GET` text
    # scan but only on actual identifier nodes (not comments / strings).
    private def extract_methods(body : LibTreeSitter::TSNode, source : String) : Array(String)
      methods = [] of String
      walk(body) do |node|
        next unless Noir::TreeSitter.node_type(node) == "scoped_identifier"
        text = Noir::TreeSitter.node_text(node, source)
        next unless text.starts_with?("Method::")
        verb = text.sub("Method::", "")
        methods << verb if HTTP_METHODS.includes?(verb) && !methods.includes?(verb)
      end
      methods
    end

    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # Pull extractor params from `request.<verb>(...)` calls in the
    # body. Recognises both plain (`request.path_parameter("id")`) and
    # turbofish (`request.path_parameter::<i64>("id")`) forms because
    # tree-sitter normalises them to the same `call_expression` shape
    # (the turbofish is a `generic_function` wrapping the field
    # expression).
    private def extract_controller_params(body : LibTreeSitter::TSNode,
                                          source : String,
                                          endpoint : Endpoint)
      existing_path_params = endpoint.params.select { |p| p.param_type == "path" }.map(&.name).to_set

      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        method_name = request_method_name(call, source)
        next unless method_name

        case method_name
        when "path_parameter"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !existing_path_params.includes?(name)
            endpoint.push_param(Param.new(name, "", "path"))
          end
        when "query_parameter"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "query" }
            endpoint.push_param(Param.new(name, "", "query"))
          end
        when "body"
          unless endpoint.params.any? { |p| p.name == "body" && p.param_type == "json" }
            endpoint.push_param(Param.new("body", "", "json"))
          end
        when "form_data"
          unless endpoint.params.any? { |p| p.name == "form" && p.param_type == "form" }
            endpoint.push_param(Param.new("form", "", "form"))
          end
        when "header"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            endpoint.push_param(Param.new(name, "", "header"))
          end
        when "cookie"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        end
      end
    end

    # Returns the trailing method name when the call shape is
    # `request.<name>(...)` (with or without turbofish), `nil`
    # otherwise.
    private def request_method_name(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node

      target =
        case Noir::TreeSitter.node_type(fn_node)
        when "field_expression"
          fn_node
        when "generic_function"
          inner = Noir::TreeSitter.field(fn_node, "function")
          inner if inner && Noir::TreeSitter.node_type(inner) == "field_expression"
        end
      return unless target

      receiver = Noir::TreeSitter.field(target, "value")
      return unless receiver && Noir::TreeSitter.node_type(receiver) == "identifier"
      return unless Noir::TreeSitter.node_text(receiver, source) == "request"

      field = Noir::TreeSitter.field(target, "field")
      return unless field
      Noir::TreeSitter.node_text(field, source)
    end

    private def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      result : String? = nil
      walk(node) do |child|
        next if result
        if Noir::TreeSitter.node_type(child) == "string_literal"
          Noir::TreeSitter.each_named_child(child) do |grand|
            if Noir::TreeSitter.node_type(grand) == "string_content"
              result = Noir::TreeSitter.node_text(grand, source)
              break
            end
          end
        end
      end
      result
    end

    private def walk(node : LibTreeSitter::TSNode, &block : LibTreeSitter::TSNode ->)
      block.call(node)
      Noir::TreeSitter.each_named_child(node) do |child|
        walk(child, &block)
      end
    end
  end
end
