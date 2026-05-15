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
      include_callee = any_to_bool(@options["include_callee"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        each_routing_pair(root) do |attr, function|
          route = extract_route(attr, source)
          next unless route
          route_path, method, attr_row = route

          details = Details.new(PathInfo.new(path, attr_row))
          endpoint = Endpoint.new(route_path, method, details)

          extract_path_params(route_path, endpoint)
          extract_function_params(function, source, endpoint)
          attach_handler_callees(function, source, path, endpoint) if include_callee

          endpoints << endpoint
        end
      end

      endpoints
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
