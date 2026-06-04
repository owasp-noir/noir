require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Loco analyzer (tree-sitter port). Loco follows Rails conventions:
  # `pub async fn <action>` inside a controller module/impl becomes
  # a RESTful endpoint whose path/method derive from the action name.
  # Loco rides on Axum, so parameter extraction picks up the standard
  # Axum extractor types (`Path<T>`, `Query<T>`, `Json<T>`, `Form<T>`,
  # `HeaderMap`).
  class Loco < RustEngine
    REST_ACTIONS = Set{"index", "show", "new", "create", "edit", "update", "destroy", "delete"}
    HTTP_VERBS   = Set{"get", "post", "put", "delete", "patch", "head", "options", "trace"}

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      # Loco user apps consume the framework via `use loco_rs::...`;
      # the framework's own crate uses `use crate::...` internally
      # and never imports `loco_rs`. Without this gate the analyzer
      # was happily inferring routes from every `pub async fn` in any
      # Rust file, surfacing ~120 phantom endpoints in loco-rs/loco's
      # own `src/boot.rs`, `src/db.rs`, `src/storage/`, etc. — framework
      # infrastructure the user never installs. The content marker is
      # cheaper and broader than a path anchor: real Loco apps put
      # controllers under `src/controllers/` *and* import `loco_rs`,
      # so the content check alone is sufficient.
      return endpoints unless source.includes?("use loco_rs")
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      # `#[cfg(test)] mod tests { Routes::new().add("/x", get(h)); }` and
      # path-normalization test fixtures live right in the framework's
      # `src/app_routes.rs` etc.; gate them like the other Rust analyzers.
      test_regions = RustEngine.collect_cfg_test_regions(source)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)

        # Modern Loco registers routes explicitly via the builder:
        #   pub fn routes() -> Routes {
        #       Routes::new().prefix("/api/auth").add("/login", post(login))
        #   }
        # The handler functions are usually plain `async fn` (no `pub`),
        # so the Rails-convention pass below never fires for them. When a
        # file uses this builder, the explicit routes are authoritative —
        # we return them and skip the convention pass so the two can't
        # double-count the same controller.
        explicit = extract_explicit_routes(root, source, path, function_index, include_callee, test_regions)
        if !explicit.empty?
          endpoints.concat(explicit)
          next
        end

        # Rails-convention fallback: only controller files. Loco never
        # auto-derives routes from a `pub async fn` name — routes are
        # always registered through the `Routes::new().add(...)` builder
        # handled above. The convention pass exists purely as a
        # best-effort guess for controller files that omit an explicit
        # builder; running it anywhere else turns every `pub async fn`
        # in `src/models/`, `src/mailers/`, `src/workers/`, … into a
        # phantom GET endpoint (15 FPs on the stock SaaS starter alone).
        next unless controller_path?(path)

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "function_item"
          next if RustEngine.inside_test_region?(node, test_regions)
          next unless public_async?(node, source)
          name_node = Noir::TreeSitter.field(node, "name")
          next unless name_node
          action = Noir::TreeSitter.node_text(name_node, source)

          endpoint_path = action_to_path(action, path)
          http_method = infer_http_method(action, node, source)
          details = Details.new(PathInfo.new(path, Noir::TreeSitter.node_start_row(node) + 1))
          endpoint = Endpoint.new(endpoint_path, http_method, details)

          extract_path_params(endpoint_path, endpoint)
          extract_function_params(node, source, endpoint)
          attach_handler_callees(node, source, path, endpoint) if include_callee

          endpoints << endpoint
        end
      end

      endpoints
    end

    # Walk every `.add("/path", get(handler))` registration on a
    # `Routes::new()` builder chain. Each `.add` is its own
    # `call_expression`; the controller-level `.prefix("…")` sits deeper
    # in the same receiver chain, so we walk up from the `.add` to find
    # it. A method-router second argument (`get(h)` / `get(h).post(h2)`)
    # can register more than one verb, so a single `.add` may yield
    # several endpoints.
    private def extract_explicit_routes(root : LibTreeSitter::TSNode,
                                        source : String,
                                        path : String,
                                        function_index : Hash(String, LibTreeSitter::TSNode),
                                        include_callee : Bool,
                                        test_regions : Array(Tuple(Int32, Int32))) : Array(Endpoint)
      endpoints = [] of Endpoint
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        next if RustEngine.inside_test_region?(node, test_regions)
        fn_node = Noir::TreeSitter.field(node, "function")
        next unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
        field = Noir::TreeSitter.field(fn_node, "field")
        next unless field && Noir::TreeSitter.node_text(field, source) == "add"

        args = Noir::TreeSitter.field(node, "arguments")
        next unless args
        route_path = first_string_literal_text(args, source)
        # Route paths are always string literals beginning with `/`; this
        # filters out unrelated `.add(...)` calls (sets, vectors, …).
        next unless route_path && route_path.starts_with?("/")

        verb_handlers = collect_method_handlers(args, source)
        next if verb_handlers.empty?

        prefix = find_chain_prefix(node, source)
        full_path = join_paths(prefix, route_path)
        row = Noir::TreeSitter.node_start_row(node) + 1

        verb_handlers.each do |verb, handler_name|
          details = Details.new(PathInfo.new(path, row))
          endpoint = Endpoint.new(full_path, verb.upcase, details)
          extract_path_params(full_path, endpoint)

          if handler_name && (handler_function = function_index[handler_name.split("::").last]?)
            extract_function_params(handler_function, source, endpoint)
            attach_handler_callees(handler_function, source, path, endpoint) if include_callee
          end

          endpoints << endpoint
        end
      end
      endpoints
    end

    # The method-router second argument to `.add`. Walks the subtree for
    # every verb call — `get(handler)` (function is the identifier `get`)
    # and chained `get(h).post(h2)` (function is a `field_expression`
    # whose field is `post`). Returns `[{verb, handler_name?}]`.
    private def collect_method_handlers(args : LibTreeSitter::TSNode,
                                        source : String) : Array(Tuple(String, String?))
      result = [] of Tuple(String, String?)
      walk(args) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        fn_node = Noir::TreeSitter.field(node, "function")
        next unless fn_node
        verb =
          case Noir::TreeSitter.node_type(fn_node)
          when "identifier"
            Noir::TreeSitter.node_text(fn_node, source)
          when "field_expression"
            (f = Noir::TreeSitter.field(fn_node, "field")) ? Noir::TreeSitter.node_text(f, source) : ""
          else
            ""
          end
        next unless HTTP_VERBS.includes?(verb)
        result << {verb, first_identifier_argument(node, source)}
      end
      result
    end

    # Walk up the `.add(...)` receiver chain looking for `.prefix("…")`
    # registered earlier on the same `Routes::new()` builder.
    private def find_chain_prefix(add_call : LibTreeSitter::TSNode, source : String) : String?
      node = add_call
      # Bounded walk; controller chains are short but guard anyway.
      256.times do
        fn = Noir::TreeSitter.field(node, "function")
        return unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
        name = (f = Noir::TreeSitter.field(fn, "field")) ? Noir::TreeSitter.node_text(f, source) : ""
        receiver = Noir::TreeSitter.field(fn, "value")
        if name == "prefix"
          if pfx = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
            return pfx
          end
        end
        return unless receiver && Noir::TreeSitter.node_type(receiver) == "call_expression"
        node = receiver
      end
      nil
    end

    private def join_paths(prefix : String?, route_path : String) : String
      p = (prefix || "").strip
      return ensure_leading_slash(route_path) if p.empty?
      combined = "/#{p.strip('/')}/#{route_path.lstrip('/')}"
      combined = combined.rstrip('/')
      combined.empty? ? "/" : combined
    end

    private def ensure_leading_slash(route_path : String) : String
      route_path.starts_with?("/") ? route_path : "/#{route_path}"
    end

    private def first_identifier_argument(call : LibTreeSitter::TSNode, source : String) : String?
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

    # Loco analysers are scoped to `pub async fn` items only — the
    # legacy regex `pub\s+async\s+fn\s+(\w+)` enforced both modifiers.
    # tree-sitter exposes them as children of the `function_item`'s
    # `visibility_modifier` and `function_modifiers` nodes.
    private def public_async?(function : LibTreeSitter::TSNode, source : String) : Bool
      has_pub = false
      has_async = false
      Noir::TreeSitter.each_named_child(function) do |child|
        case Noir::TreeSitter.node_type(child)
        when "visibility_modifier"
          has_pub = Noir::TreeSitter.node_text(child, source).starts_with?("pub")
        when "function_modifiers"
          has_async = Noir::TreeSitter.node_text(child, source).includes?("async")
        end
      end
      has_pub && has_async
    end

    private def action_to_path(action : String, file_path : String) : String
      controller = controller_name_from_path(file_path)

      case action
      when "index"
        controller.empty? ? "/" : "/#{controller}"
      when "show"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      when "new"
        controller.empty? ? "/new" : "/#{controller}/new"
      when "create"
        controller.empty? ? "/" : "/#{controller}"
      when "edit"
        controller.empty? ? "/:id/edit" : "/#{controller}/:id/edit"
      when "update", "destroy", "delete"
        controller.empty? ? "/:id" : "/#{controller}/:id"
      else
        base_path = controller.empty? ? "" : "/#{controller}"
        "#{base_path}/#{action.gsub(/([A-Z])/, "_\\1").downcase.lstrip("_")}"
      end
    end

    # Loco controllers live under `src/controllers/` (the framework
    # generator never puts them anywhere else). The `*_controller.rs`
    # basename is also accepted for projects that keep a flatter layout.
    private def controller_path?(file_path : String) : Bool
      return true if file_path.includes?("/controllers/") || file_path.includes?("/controller/")
      File.basename(file_path).ends_with?("_controller.rs")
    end

    private def controller_name_from_path(file_path : String) : String
      return "" unless file_path.includes?("/controllers/") || file_path.includes?("/controller/")
      file = file_path.split("/").last.gsub(/\.rs$/, "")
      file.gsub(/_controller$/, "")
    end

    private def infer_http_method(action : String, function : LibTreeSitter::TSNode, source : String) : String
      case action
      when "index", "show", "new", "edit"
        "GET"
      when "create", "login", "signup", "register"
        "POST"
      when "update"
        signature_text(function, source).includes?("PUT") ? "PUT" : "PATCH"
      when "destroy", "delete"
        "DELETE"
      else
        sig = signature_text(function, source)
        return "POST" if sig.includes?("Form<")
        return "POST" if sig =~ /\bpost\b/i
        return "PUT" if sig =~ /\bput\b/i
        return "DELETE" if sig =~ /\bdelete\b/i
        return "PATCH" if sig =~ /\bpatch\b/i
        "GET"
      end
    end

    # Function signature minus the body — used by `infer_http_method`
    # so we don't get false hits on `let post = …` style locals.
    private def signature_text(function : LibTreeSitter::TSNode, source : String) : String
      params = Noir::TreeSitter.field(function, "parameters")
      return "" unless params
      return_type = Noir::TreeSitter.field(function, "return_type")
      start_byte = LibTreeSitter.ts_node_start_byte(function).to_i
      end_byte =
        if return_type
          LibTreeSitter.ts_node_end_byte(return_type).to_i
        else
          LibTreeSitter.ts_node_end_byte(params).to_i
        end
      source.byte_slice(start_byte, end_byte - start_byte)
    end

    # Loco/Axum path params come in two flavours: the legacy colon form
    # (`/:id`) used by the Rails-convention pass and the brace form
    # (`/{id}`, `/{*rest}`, `/{**path}`) used by modern explicit routes.
    # Strip any leading capture markers (`*`) so the param name stays
    # clean.
    private def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        name = match[1]
        endpoint.push_param(Param.new(name, "", "path")) unless endpoint.params.any? { |p| p.name == name && p.param_type == "path" }
      end
      route.scan(/\{\**(\w+)\}/) do |match|
        name = match[1]
        endpoint.push_param(Param.new(name, "", "path")) unless endpoint.params.any? { |p| p.name == name && p.param_type == "path" }
      end
    end

    # Loco rides on Axum; extractor types appear in the parameter
    # list. Query / Json / Form get default param names matching the
    # legacy analyzer; Path<T> is already captured from the route
    # pattern.
    private def extract_function_params(function : LibTreeSitter::TSNode,
                                        source : String,
                                        endpoint : Endpoint)
      params = Noir::TreeSitter.field(function, "parameters")
      has_header_map = false
      if params
        Noir::TreeSitter.each_named_child(params) do |param|
          text = Noir::TreeSitter.node_text(param, source)
          if text.includes?("Query<") && !endpoint.params.any? { |p| p.name == "query" && p.param_type == "query" }
            endpoint.push_param(Param.new("query", "", "query"))
          end
          if text.includes?("Json<") && !endpoint.params.any? { |p| p.name == "body" && p.param_type == "json" }
            endpoint.push_param(Param.new("body", "", "json"))
          end
          if text.includes?("Form<") && !endpoint.params.any? { |p| p.name == "form" && p.param_type == "form" }
            endpoint.push_param(Param.new("form", "", "form"))
          end
          has_header_map = true if text.includes?("HeaderMap")
        end
      end

      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        fn_text = call_function_text(call, source)
        next if fn_text.nil?

        if has_header_map && (fn_text.ends_with?(".get") || fn_text == "get")
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && header_name?(name) && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            endpoint.push_param(Param.new(name, "", "header"))
          end
        elsif fn_text.ends_with?(".cookie") || fn_text == "cookie"
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        end
      end
    end

    # The legacy analyzer only kept header-like strings (with a dash
    # or one of the canonical names) to avoid capturing every random
    # `.get("foo")` inside the body.
    private def header_name?(name : String) : Bool
      name.includes?("-") || name.in?(%w[Authorization Content-Type Accept])
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
