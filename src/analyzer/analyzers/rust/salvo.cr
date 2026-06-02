require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Salvo analyzer (tree-sitter port). Salvo wires routes in two
  # shapes, both handled here:
  #
  #   1. Router-chain DSL:
  #        Router::with_path("users/<id>").get(get_user)
  #        Router::new().path("users").hoop(auth).get(list).post(create)
  #      Each `.<verb>(handler)` is paired with the nearest enclosing
  #      `.with_path(...)` / `.path(...)` found by walking up its
  #      receiver chain — so middleware (`.hoop(...)`) and verb chaining
  #      (`.get(a).post(b)`) between the path and the verb don't break
  #      detection.
  #
  #   2. Attribute macro:
  #        #[endpoint(method = Post, path = "/api/submit/<id>")]
  #        async fn submit_form(...) { ... }
  #
  # Router chains are frequently assembled inside a `vec![ ... ]` macro
  # (`impl Routers { fn build() -> Vec<Router> { vec![Router::new()…] } }`).
  # tree-sitter leaves a macro body as a flat `token_tree` with no
  # `call_expression` nodes, so those routes are invisible to a plain
  # AST walk. We recover them by re-parsing each router-bearing macro
  # body as an expression fragment and mapping line numbers back.
  class Salvo < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      # `crates/core/src/routing.rs`-style `#[cfg(test)] mod tests
      # { Router::with_path(...).get(...) }` blocks would otherwise
      # leak into the endpoint set. See `RustEngine.collect_cfg_test_regions`
      # for the shared helper's rationale.
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)

        # 1. Router chains visible in the real AST.
        collect_chain_endpoints(root, source, source, path, function_index,
          include_callee, 0, test_regions, endpoints)

        # 2. `#[endpoint(...)]` attribute macros.
        each_routing_pair(root) do |attr_item, function|
          next if RustEngine.inside_test_region?(attr_item, test_regions)
          route = decode_endpoint_macro(attr_item, source)
          next unless route
          route_path, method, attr_row = route

          details = Details.new(PathInfo.new(path, attr_row))
          endpoint = Endpoint.new(route_path, method, details)
          extract_path_params(route_path, endpoint)
          extract_function_params(function, source, endpoint)
          attach_handler_callees(function, source, path, endpoint) if include_callee

          endpoints << endpoint
        end

        # 3. Router chains hidden inside `vec![ ... ]` (and similar)
        # macro bodies. Each fragment is re-parsed with its own
        # source/row offset, but handler functions are still resolved in
        # the real tree's index (handlers live outside the macro).
        collect_router_macro_fragments(root, source, test_regions).each do |fragment, row_offset|
          Noir::TreeSitter.parse_rust(fragment) do |frag_root|
            collect_chain_endpoints(frag_root, fragment, source, path, function_index,
              include_callee, row_offset, nil, endpoints)
          end
        end
      end

      endpoints
    end

    # Walk `chain_root` for `.<verb>(handler)` calls and emit an endpoint
    # for each one whose receiver chain contains a `.with_path(...)` /
    # `.path(...)`. `chain_source` is the text the route nodes belong to
    # (the file, or a re-parsed macro fragment); `original_source` is the
    # file text used for handler-function nodes resolved via the index.
    # `row_offset` maps fragment rows back onto the file.
    private def collect_chain_endpoints(chain_root : LibTreeSitter::TSNode,
                                        chain_source : String,
                                        original_source : String,
                                        path : String,
                                        function_index : Hash(String, LibTreeSitter::TSNode),
                                        include_callee : Bool,
                                        row_offset : Int32,
                                        test_regions : Array(Tuple(Int32, Int32))?,
                                        endpoints : Array(Endpoint))
      walk(chain_root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        next if test_regions && RustEngine.inside_test_region?(node, test_regions)
        chain = decode_router_chain(node, chain_source)
        next unless chain
        route_path, method, handler_name = chain

        row = Noir::TreeSitter.node_start_row(node) + 1 + row_offset
        details = Details.new(PathInfo.new(path, row))
        endpoint = Endpoint.new("/#{route_path.lstrip('/')}", method, details)
        extract_path_params(route_path, endpoint)

        if handler_name && (handler_function = function_index[handler_name.split("::").last]?)
          extract_function_params(handler_function, original_source, endpoint)
          attach_handler_callees(handler_function, original_source, path, endpoint) if include_callee
        end

        endpoints << endpoint
      end
    end

    # `<chain>.<verb>(handler)` → `{path, METHOD, handler_name?}` or
    # `nil`. The verb method is an HTTP verb and the receiver chain must
    # carry a `.with_path(...)` / `.path(...)`. The handler may be a
    # scoped path (`html::pages::login`) or absent (`get(StaticDir::…)`);
    # either way the route is still emitted — the handler is only used to
    # enrich params/callees.
    private def decode_router_chain(call : LibTreeSitter::TSNode, source : String) : Tuple(String, String, String?)?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
      verb_field = Noir::TreeSitter.field(fn_node, "field")
      return unless verb_field
      verb = Noir::TreeSitter.node_text(verb_field, source).downcase
      return unless HTTP_VERBS.includes?(verb)

      route_path = find_chain_path(fn_node, source)
      return unless route_path

      handler_name = first_handler_argument(call, source)
      {route_path, verb.upcase, handler_name}
    end

    # Walk up the receiver chain from a `.<verb>(...)` field expression
    # looking for the nearest `.with_path("…")` / `.path("…")`. Returns
    # its route string, or `nil` if the chain isn't a router chain (which
    # is how non-routing `.get(...)` calls — `map.get(k)`,
    # `req.headers().get("X")` — are filtered out).
    private def find_chain_path(verb_fn : LibTreeSitter::TSNode, source : String) : String?
      receiver = Noir::TreeSitter.field(verb_fn, "value")
      256.times do
        return unless receiver && Noir::TreeSitter.node_type(receiver) == "call_expression"
        rfn = Noir::TreeSitter.field(receiver, "function")
        return unless rfn
        case Noir::TreeSitter.node_type(rfn)
        when "field_expression"
          name = (f = Noir::TreeSitter.field(rfn, "field")) ? Noir::TreeSitter.node_text(f, source) : ""
          if name == "with_path" || name == "path"
            return first_string_literal_text(Noir::TreeSitter.field(receiver, "arguments"), source)
          end
          receiver = Noir::TreeSitter.field(rfn, "value")
        when "scoped_identifier"
          # Chain base such as `Router::with_path("…")` or `Router::new()`.
          name = Noir::TreeSitter.node_text(rfn, source).split("::").last
          if name == "with_path" || name == "path"
            return first_string_literal_text(Noir::TreeSitter.field(receiver, "arguments"), source)
          end
          return
        else
          return
        end
      end
      nil
    end

    # `#[endpoint(method = Post, path = "/x")]`. tree-sitter-rust
    # leaves the macro arguments as a `token_tree`, but the inner
    # tokens are still tagged — we look for the `method` / `path`
    # keywords and pull the following identifier / string literal.
    private def decode_endpoint_macro(attr_item : LibTreeSitter::TSNode,
                                      source : String) : Tuple(String, String, Int32)?
      attr = find_named_child(attr_item, "attribute")
      return unless attr

      attr_name = nil.as(String?)
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          attr_name = Noir::TreeSitter.node_text(child, source)
          break
        end
      end
      return unless attr_name == "endpoint"

      arguments = Noir::TreeSitter.field(attr, "arguments")
      return unless arguments

      method = "GET"
      route_path = "/"
      saw_method = false
      saw_path = false
      Noir::TreeSitter.each_named_child(arguments) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier"
          name = Noir::TreeSitter.node_text(child, source)
          case name
          when "method"
            saw_method = true
          when "path"
            saw_path = true
          else
            method = name.upcase if saw_method
            saw_method = false
          end
        when "string_literal"
          if saw_path
            text = string_content(child, source)
            route_path = text if text
            saw_path = false
          end
        end
      end
      {route_path, method, Noir::TreeSitter.node_start_row(attr_item) + 1}
    end

    # Salvo path params come in two flavours: the legacy angle form
    # (`<id>`) and the modern brace form (`{id}`, `{*rest}`, `{**path}`,
    # and regex-constrained `{id|[0-9]+}`). Strip capture markers and any
    # inline regex constraint so the param name stays clean.
    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/<(\w+)>/) do |match|
        push_path_param(endpoint, match[1])
      end
      route.scan(/\{\**(\w+)(?:\|[^}]*)?\}/) do |match|
        push_path_param(endpoint, match[1])
      end
    end

    private def push_path_param(endpoint : Endpoint, name : String)
      return if endpoint.params.any? { |p| p.name == name && p.param_type == "path" }
      endpoint.push_param(Param.new(name, "", "path"))
    end

    # Walk parameters + body looking for QueryParam / JsonBody /
    # FormBody / req.header / req.cookie shapes. Bounded to the
    # function so unrelated calls in the file don't bleed in.
    private def extract_function_params(function : LibTreeSitter::TSNode,
                                        source : String,
                                        endpoint : Endpoint)
      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |node|
        text = Noir::TreeSitter.node_text(node, source)
        case Noir::TreeSitter.node_type(node)
        when "let_declaration", "type_identifier", "scoped_type_identifier", "generic_type"
          if text.includes?("QueryParam") && !endpoint.params.any? { |p| p.name == "query" && p.param_type == "query" }
            endpoint.push_param(Param.new("query", "", "query"))
          end
          if text.includes?("JsonBody") && !endpoint.params.any? { |p| p.name == "body" && p.param_type == "json" }
            endpoint.push_param(Param.new("body", "", "json"))
          end
          if text.includes?("FormBody") && !endpoint.params.any? { |p| p.name == "form" && p.param_type == "form" }
            endpoint.push_param(Param.new("form", "", "form"))
          end
        when "call_expression"
          fn_text = call_function_text(node, source)
          next if fn_text.nil?
          if fn_text == "req.query" && !endpoint.params.any? { |p| p.name == "query" && p.param_type == "query" }
            endpoint.push_param(Param.new("query", "", "query"))
          end
          if fn_text == "req.header" || fn_text.ends_with?("req.headers().get")
            if name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
              endpoint.push_param(Param.new(name, "", "header")) unless endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            end
          end
          if fn_text == "req.cookie"
            if name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
              endpoint.push_param(Param.new(name, "", "cookie")) unless endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
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

    # First identifier / scoped-path argument of a call, used as the
    # handler name. `get(create_user)` → `create_user`,
    # `get(html::pages::login)` → `html::pages::login`.
    private def first_handler_argument(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      Noir::TreeSitter.each_named_child(args) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          return Noir::TreeSitter.node_text(child, source)
        end
      end
      nil
    end

    # Collect re-parseable expression fragments for every macro body that
    # mentions `Router`, paired with the 0-based row of the macro's
    # `token_tree` so detected routes map back to their real file line.
    private def collect_router_macro_fragments(root : LibTreeSitter::TSNode,
                                               source : String,
                                               test_regions : Array(Tuple(Int32, Int32))) : Array(Tuple(String, Int32))
      fragments = [] of Tuple(String, Int32)
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "macro_invocation"
        next if RustEngine.inside_test_region?(node, test_regions)
        token_tree = nil.as(LibTreeSitter::TSNode?)
        Noir::TreeSitter.each_named_child(node) do |child|
          token_tree = child if Noir::TreeSitter.node_type(child) == "token_tree"
        end
        next unless tt = token_tree
        text = Noir::TreeSitter.node_text(tt, source)
        next unless text.includes?("Router")
        # The prefix carries no newline, so the token_tree's text keeps
        # its original relative line layout and `node_start_row(tt)` is
        # the row offset that maps fragment rows onto the file.
        fragments << {"fn __noir_salvo_wf() { let __noir_x = #{text}; }", Noir::TreeSitter.node_start_row(tt)}
      end
      fragments
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
          return
        end
      end
      nil
    end

    private def first_string_literal_text(node : LibTreeSitter::TSNode?, source : String) : String?
      return unless node
      result : String? = nil
      walk(node) do |child|
        next if result
        if Noir::TreeSitter.node_type(child) == "string_literal"
          result = string_content(child, source)
        end
      end
      result
    end

    private def string_content(string_literal : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(string_literal) do |grand|
        return Noir::TreeSitter.node_text(grand, source) if Noir::TreeSitter.node_type(grand) == "string_content"
      end
      nil
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
