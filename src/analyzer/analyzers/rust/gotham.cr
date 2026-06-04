require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Gotham analyzer (tree-sitter port). Gotham wires routes with a
  # builder chain that pairs each verb call with a following `.to`:
  #
  #     Router::builder()
  #         .get("/users/:id").to(user_handler)
  #         .post("/users").to(create_user_handler)
  #
  # The analyzer walks `call_expression` nodes whose function is a
  # `field_expression` named `to` — the receiver of `.to(handler)` is
  # the `.<verb>("/path")` call, so each routing entry has both
  # pieces locally and we don't need to thread state through the
  # chain.
  class Gotham < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # Gotham's framework repo parks route registrations inside
      # `#[cfg(test)] mod tests { ... build_router(|route| { route.get(...) }) }`
      # blocks (e.g. `router/builder/mod.rs`). Gate them out like the other
      # Rust analyzers do, via the shared cfg(test) region scan.
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)
        walk_with_prefix(root, source, "", path, function_index, include_callee, endpoints, test_regions)
      end

      endpoints
    end

    # Recursive descent that threads the current path prefix. Gotham's
    # `build_router(|route| { ... })` groups routes under
    # `route.scope("/api", |route| { ... })` closures (which prepend a
    # path segment) and `route.with_pipeline_chain(chain, |route| { ... })`
    # closures (which only add middleware). A flat walk reported the
    # inner path verbatim — `/users` instead of `/api/users`. We now
    # descend into each closure carrying the accumulated prefix.
    private def walk_with_prefix(node : LibTreeSitter::TSNode,
                                 source : String,
                                 prefix : String,
                                 path : String,
                                 function_index : Hash(String, LibTreeSitter::TSNode),
                                 include_callee : Bool,
                                 endpoints : Array(Endpoint),
                                 test_regions : Array(Tuple(Int32, Int32)))
      if Noir::TreeSitter.node_type(node) == "call_expression" && !RustEngine.inside_test_region?(node, test_regions)
        if scope = decode_scope(node, source)
          seg, block = scope
          walk_with_prefix(block, source, join_paths(prefix, seg), path, function_index, include_callee, endpoints, test_regions)
          return
        end
        if block = decode_pipeline_closure(node, source)
          walk_with_prefix(block, source, prefix, path, function_index, include_callee, endpoints, test_regions)
          return
        end
        if assoc = decode_associate(node, source)
          assoc_path, closure_body = assoc
          process_associate(closure_body, source, join_paths(prefix, assoc_path), path, function_index, include_callee, endpoints)
          # fall through to the generic child walk so any nested
          # scope/route inside the closure is still visited.
        end
        if route = decode_to_call(node, source)
          route_path, methods, handler_name = route
          full_path = join_paths(prefix, route_path)

          methods.each do |method|
            details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
            endpoint = Endpoint.new(full_path, method, details)
            extract_path_params(full_path, endpoint)

            if handler_name && (handler_function = function_index[handler_name]?)
              scan_function(handler_function, source, endpoint)
              attach_handler_callees(handler_function, source, path, endpoint) if include_callee
            end

            endpoints << endpoint
          end
        end
      end

      Noir::TreeSitter.each_named_child(node) do |child|
        walk_with_prefix(child, source, prefix, path, function_index, include_callee, endpoints, test_regions)
      end
    end

    # `route.scope("/seg", |route| { ... })` → `{seg, closure_body}`.
    private def decode_scope(call : LibTreeSitter::TSNode, source : String) : Tuple(String, LibTreeSitter::TSNode)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field && Noir::TreeSitter.node_text(field, source) == "scope"

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      seg = first_string_literal_text(args, source)
      return unless seg
      block = closure_body(args)
      return unless block
      {seg, block}
    end

    # Pipeline-grouping closures (`with_pipeline_chain`, `with_pipeline`)
    # wrap routes with middleware without changing the path. Returns the
    # closure body so the caller can descend with the same prefix.
    private def decode_pipeline_closure(call : LibTreeSitter::TSNode, source : String) : LibTreeSitter::TSNode?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field
      name = Noir::TreeSitter.node_text(field, source)
      return unless name == "with_pipeline_chain" || name == "with_pipeline"
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      closure_body(args)
    end

    # Body block of the first closure argument in an `arguments` node.
    private def closure_body(args : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      Noir::TreeSitter.each_named_child(args) do |arg|
        next unless Noir::TreeSitter.node_type(arg) == "closure_expression"
        body = Noir::TreeSitter.field(arg, "body")
        return body if body && Noir::TreeSitter.node_type(body) == "block"
        Noir::TreeSitter.each_named_child(arg) do |child|
          return child if Noir::TreeSitter.node_type(child) == "block"
        end
      end
      nil
    end

    private def join_paths(prefix : String, route_path : String) : String
      return ensure_leading_slash(route_path) if prefix.empty?
      combined = "/#{prefix.strip('/')}/#{route_path.lstrip('/')}".rstrip('/')
      combined.empty? ? "/" : combined
    end

    private def ensure_leading_slash(route_path : String) : String
      route_path.starts_with?("/") ? route_path : "/#{route_path}"
    end

    # Route terminals: `.to(handler)` binds a handler fn; `.to_file` /
    # `.to_dir` / `.to_new_handler` bind static/dynamic handlers (no fn
    # name, but still a real route).
    TERMINAL_NAMES = Set{"to", "to_file", "to_dir", "to_new_handler", "to_async_borrowing"}

    # `.<verb>("/x")[.with_*_extractor::<T>()]*.to(handler)` →
    # `{path, [METHODS], handler_name?}` or `nil`. Walks the `.to`
    # receiver chain UP through extractor / matcher methods
    # (`with_path_extractor`, `with_query_string_extractor`, …) to the
    # verb call, so a typed-extractor pipeline between verb and `.to`
    # doesn't break detection. Handles the `get_or_head` convenience verb
    # and the multi-method `request(vec![Method::GET, …], "/p")` form.
    private def decode_to_call(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(String), String?)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field && TERMINAL_NAMES.includes?(Noir::TreeSitter.node_text(field, source))

      receiver = Noir::TreeSitter.field(fn_node, "value")
      return unless receiver
      verb_call = find_verb_call(receiver, source)
      return unless verb_call
      route_path, methods = verb_call

      handler = Noir::TreeSitter.node_text(field, source) == "to" ? first_identifier_argument(call, source) : nil
      {route_path, methods, handler}
    end

    # A method call's `{field_name, receiver}`, peeling a `generic_function`
    # turbofish wrapper (`x.with_path_extractor::<T>()` parses as a
    # generic_function whose function is the `x.with_path_extractor`
    # field_expression). Returns `nil` for non-method calls.
    private def method_field_and_receiver(call : LibTreeSitter::TSNode, source : String) : Tuple(String, LibTreeSitter::TSNode?)?
      fn = Noir::TreeSitter.field(call, "function")
      return unless fn
      fn = Noir::TreeSitter.field(fn, "function") if Noir::TreeSitter.node_type(fn) == "generic_function"
      return unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
      field = Noir::TreeSitter.field(fn, "field")
      return unless field
      {Noir::TreeSitter.node_text(field, source), Noir::TreeSitter.field(fn, "value")}
    end

    # Walk a `.to` receiver chain up through intermediate (non-verb)
    # method calls until a verb call is found; return its `{path, [methods]}`.
    private def find_verb_call(node : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(String))?
      cursor = node
      256.times do
        return unless cursor && Noir::TreeSitter.node_type(cursor) == "call_expression"
        mfr = method_field_and_receiver(cursor, source)
        return unless mfr
        if decoded = decode_verb_call(cursor, source)
          return decoded
        end
        cursor = mfr[1]
      end
      nil
    end

    # Decode a single verb call: `.get("/p")`, `.get_or_head("/p")`, or
    # `.request(vec![Method::GET, Method::HEAD], "/p")`. Returns
    # `{path, [METHODS]}` or `nil` if the field isn't a verb.
    private def decode_verb_call(call : LibTreeSitter::TSNode, source : String) : Tuple(String, Array(String))?
      mfr = method_field_and_receiver(call, source)
      return unless mfr
      name = mfr[0].downcase

      if HTTP_VERBS.includes?(name)
        path = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
        return unless path
        return {path, [name.upcase]}
      end

      if name == "get_or_head"
        path = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
        return unless path
        return {path, ["GET", "HEAD"]}
      end

      if name == "request"
        args = Noir::TreeSitter.field(call, "arguments")
        return unless args
        named = [] of LibTreeSitter::TSNode
        Noir::TreeSitter.each_named_child(args) { |c| named << c }
        return if named.size < 2
        methods = parse_method_vec(named[0], source)
        return if methods.empty?
        path = first_string_literal_text(named[1], source)
        return unless path
        return {path, methods}
      end

      nil
    end

    # `vec![Method::GET, Method::HEAD]` → `["GET", "HEAD"]`. tree-sitter
    # leaves a `vec!` body as a flat `token_tree` (no `scoped_identifier`
    # nodes), so we scan the macro text for the verb constants directly.
    private def parse_method_vec(node : LibTreeSitter::TSNode, source : String) : Array(String)
      text = Noir::TreeSitter.node_text(node, source)
      methods = [] of String
      text.scan(/\b(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b/) do |m|
        methods << m[1]
      end
      methods.uniq
    end

    # `route.associate("/path", |assoc| { assoc.get().to(h); ... })` →
    # `{path, closure_body}`. Each `assoc.<verb>()` inside the closure
    # carries no path of its own — they all register under `/path`.
    private def decode_associate(call : LibTreeSitter::TSNode, source : String) : Tuple(String, LibTreeSitter::TSNode)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      field = Noir::TreeSitter.field(fn_node, "field")
      return unless field && Noir::TreeSitter.node_text(field, source) == "associate"
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      assoc_path = first_string_literal_text(args, source)
      return unless assoc_path
      body = closure_body(args)
      return unless body
      {assoc_path, body}
    end

    # Emit endpoints for an `associate` closure: every `assoc.<verb>().to(h)`
    # (or `.to_file` / `.to_dir`) inside registers under `assoc_path`.
    private def process_associate(closure_body : LibTreeSitter::TSNode,
                                  source : String,
                                  assoc_path : String,
                                  path : String,
                                  function_index : Hash(String, LibTreeSitter::TSNode),
                                  include_callee : Bool,
                                  endpoints : Array(Endpoint))
      walk(closure_body) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        fn_node = Noir::TreeSitter.field(node, "function")
        next unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
        field = Noir::TreeSitter.field(fn_node, "field")
        next unless field && TERMINAL_NAMES.includes?(Noir::TreeSitter.node_text(field, source))

        methods = associate_verb_methods(Noir::TreeSitter.field(fn_node, "value"), source)
        next if methods.empty?
        handler = Noir::TreeSitter.node_text(field, source) == "to" ? first_identifier_argument(node, source) : nil

        methods.each do |method|
          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
          endpoint = Endpoint.new(assoc_path, method, details)
          extract_path_params(assoc_path, endpoint)
          if handler && (handler_function = function_index[handler]?)
            scan_function(handler_function, source, endpoint)
            attach_handler_callees(handler_function, source, path, endpoint) if include_callee
          end
          endpoints << endpoint
        end
      end
    end

    # Inside an associate closure, the verb call (`assoc.get()`,
    # `assoc.get_or_head()`) has no path argument — return just its methods.
    private def associate_verb_methods(node : LibTreeSitter::TSNode?, source : String) : Array(String)
      cursor = node
      256.times do
        return [] of String unless cursor && Noir::TreeSitter.node_type(cursor) == "call_expression"
        mfr = method_field_and_receiver(cursor, source)
        return [] of String unless mfr
        name = mfr[0].downcase
        return [name.upcase] if HTTP_VERBS.includes?(name)
        return ["GET", "HEAD"] if name == "get_or_head"
        cursor = mfr[1]
      end
      [] of String
    end

    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
    end

    # Header / cookie / `header::Name` extraction from the handler
    # body. Walks `call_expression` nodes once; `header::FooBar`
    # appears as `scoped_identifier` and is converted to a header name
    # by replacing underscores with hyphens (matches the legacy
    # analyzer's gsub).
    private def scan_function(function : LibTreeSitter::TSNode,
                              source : String,
                              endpoint : Endpoint)
      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |node|
        case Noir::TreeSitter.node_type(node)
        when "call_expression"
          fn_text = call_function_text(node, source)
          next if fn_text.nil?
          if fn_text.ends_with?(".cookie")
            name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
            if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
              endpoint.push_param(Param.new(name, "", "cookie"))
            end
          elsif fn_text.ends_with?(".headers().get")
            name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
            if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
              endpoint.push_param(Param.new(name, "", "header"))
            end
          end
        when "scoped_identifier"
          text = Noir::TreeSitter.node_text(node, source)
          if text.starts_with?("header::")
            header_name = text.sub("header::", "").gsub("_", "-")
            if !endpoint.params.any? { |p| p.name == header_name && p.param_type == "header" }
              endpoint.push_param(Param.new(header_name, "", "header"))
            end
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

    private def first_identifier_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier"
          return Noir::TreeSitter.node_text(child, source)
        when "scoped_identifier"
          return Noir::TreeSitter.node_text(child, source).split("::").last
        end
      end
      nil
    end

    private def build_function_index(root : LibTreeSitter::TSNode, source : String) : Hash(String, LibTreeSitter::TSNode)
      index = {} of String => LibTreeSitter::TSNode
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        name_node = Noir::TreeSitter.field(node, "name")
        next unless name_node
        name = Noir::TreeSitter.node_text(name_node, source)
        index[name] = node unless index.has_key?(name)
      end
      index
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
