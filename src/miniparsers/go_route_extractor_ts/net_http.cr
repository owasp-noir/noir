# Part of Noir::TreeSitterGoRouteExtractor: net/http ServeMux registrations.
module Noir
  module TreeSitterGoRouteExtractor
    # Local collection of net/http import aliases (supports default "http",
    # aliased `h "net/http"`, etc). Mirrors the logic in GoCalleeExtractor
    # but kept private here to avoid widening any public surface and to stay
    # isolated from other miniparsers.
    # `root` is passed in so the caller's parse is reused: this used to
    # open its own `parse_go` and its only caller then opened a second
    # one over the same buffer, i.e. two full tree-sitter parses per
    # candidate `.go` file.
    private def collect_http_aliases(root : LibTreeSitter::TSNode, source : String) : Set(String)
      aliases = Set(String).new
      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "import_spec"

        alias_name : String? = nil
        import_path : String? = nil
        Noir::TreeSitter.each_named_child(node) do |child|
          case Noir::TreeSitter.node_type(child)
          when "package_identifier"
            alias_name = Noir::TreeSitter.node_text(child, source)
          when "interpreted_string_literal", "raw_string_literal"
            txt = Noir::TreeSitter.node_text(child, source)
            import_path = unquote_like(txt)
          end
        end

        next unless path = import_path
        next unless path == "net/http"
        name = alias_name || "http"
        next if name.empty? || name == "_" || name == "."
        aliases << name
      end
      if aliases.empty? && source.includes?("net/http")
        aliases << "http"
      end
      aliases
    end

    private def unquote_like(text : String) : String
      return text[1...-1] if text.size >= 2 && ((text.starts_with?("\"") && text.ends_with?("\"")) || (text.starts_with?("`") && text.ends_with?("`")))
      text
    end

    # Extracts routes registered directly against the Go standard library
    # `net/http` package (and its ServeMux). This covers the very common
    # bare-server pattern used in tutorials, internal tools and minimal
    # services:
    #
    #   http.HandleFunc("/hello", handler)
    #   http.Handle("/api", h)
    #
    #   mux := http.NewServeMux()
    #   mux.HandleFunc("/users", uh)
    #   mux.Handle("/old", oh)
    #
    #   // Go 1.22+ method-in-pattern form (verb is known at registration)
    #   mux.HandleFunc("POST /items", ih)
    #
    # The extractor ONLY returns registrations performed on:
    #   * the net/http package identifier (or alias: `import h "net/http"; h.HandleFunc`)
    #   * variables proven (via same-file assignment) to have originated from
    #     `http.NewServeMux()`, `&http.ServeMux{}`, or `http.ServeMux{}`
    #
    # This guarantees zero collision with chi's HandleFunc/Handle (which are
    # handled exclusively by the chi walker and would otherwise be mis-attributed
    # if we reused the generic mux handlefunc chain decoder).
    #
    # Routes are emitted with verb "ANY" (classic registrations match whatever
    # the handler decides at runtime) or the concrete verb when the modern
    # "METHOD /path" pattern form is used. Callers (the go_http analyzer) are
    # responsible for fanning ANY via `fan_out_verbs`.
    # `decode_net_http_registration` accepts a registration only when the
    # selector field is the identifier `Handle` or `HandleFunc`. An
    # identifier is a single contiguous token, so a file that does not
    # contain the substring `Handle` anywhere cannot produce a route here
    # — and 15,800 of kubernetes' 17,874 `.go` files don't. Checking that
    # first keeps the tree-sitter parse for the files that can actually
    # match.
    NET_HTTP_HANDLE_MARKER_RE = Regex.union("Handle")

    # Necessary condition for `extract_net_http_routes` to return
    # anything. Exposed so callers can skip the per-directory pre-passes
    # that only ever feed net/http route resolution.
    def net_http_route_source?(source : String) : Bool
      NET_HTTP_HANDLE_MARKER_RE.matches?(source, options: Noir::TextFile::MATCH_OPTIONS)
    end

    def extract_net_http_routes(source : String,
                                external_string_values : Hash(String, String) = Hash(String, String).new,
                                external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody) = Hash(String, Noir::GoCalleeExtractor::FunctionBody).new,
                                external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)) = Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)).new) : Array(Route)
      routes = [] of Route
      return routes unless net_http_route_source?(source)

      Noir::TreeSitter.parse_go(source) do |root|
        http_aliases = collect_http_aliases(root, source)
        next if http_aliases.empty?

        string_values = collect_string_values(root, source)
        external_string_values.each { |k, v| string_values[k] ||= v }

        serve_mux_vars = collect_serve_mux_vars(root, source, http_aliases)

        local_functions = Hash(String, LibTreeSitter::TSNode).new
        local_methods = Hash(String, LibTreeSitter::TSNode).new
        Noir::TreeSitter.each_named_child(root) do |child|
          case Noir::TreeSitter.node_type(child)
          when "function_declaration"
            if name_node = Noir::TreeSitter.field(child, "name")
              local_functions[Noir::TreeSitter.node_text(name_node, source)] = child
            end
          when "method_declaration"
            if name_node = Noir::TreeSitter.field(child, "name")
              local_methods[Noir::TreeSitter.node_text(name_node, source)] = child
            end
          end
        end

        walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "call_expression"
          decode_net_http_registration(
            node, source, http_aliases, serve_mux_vars, string_values,
            local_functions, local_methods, external_functions, external_methods
          ) do |route|
            routes << route
          end
        end
      end
      routes
    end

    # Collects names of local variables that are assigned a *http.ServeMux
    # (via NewServeMux or composite literal) inside this file. Only same-file
    # tracking is performed — cross-file ServeMux instances are out of scope
    # for the first cut (identical limitation to many other Go patterns).
    private def collect_serve_mux_vars(root : LibTreeSitter::TSNode,
                                       source : String,
                                       http_aliases : Set(String)) : Set(String)
      vars = Set(String).new
      walk(root) do |node|
        case Noir::TreeSitter.node_type(node)
        when "short_var_declaration", "assignment_statement", "var_spec"
          collect_serve_mux_assignment(node, source, http_aliases, vars)
        end
      end
      vars
    end

    private def collect_serve_mux_assignment(node : LibTreeSitter::TSNode,
                                             source : String,
                                             http_aliases : Set(String),
                                             vars : Set(String))
      left = Noir::TreeSitter.field(node, "left")
      right = Noir::TreeSitter.field(node, "right")
      if Noir::TreeSitter.node_type(node) == "var_spec"
        left = Noir::TreeSitter.field(node, "name")
        right = Noir::TreeSitter.field(node, "value")
      end
      return unless left && right

      name_nodes = [] of LibTreeSitter::TSNode
      if Noir::TreeSitter.node_type(left) == "identifier"
        name_nodes << left
      else
        Noir::TreeSitter.each_named_child(left) do |c|
          name_nodes << c if Noir::TreeSitter.node_type(c) == "identifier"
        end
      end
      return if name_nodes.empty?

      actual_rhs = right
      if Noir::TreeSitter.node_type(right) == "expression_list"
        actual_rhs = first_named_child(right) || right
      end
      if serve_mux_rhs?(actual_rhs, source, http_aliases)
        name_nodes.each do |n|
          vars << Noir::TreeSitter.node_text(n, source)
        end
      end
    end

    private def serve_mux_rhs?(node : LibTreeSitter::TSNode,
                               source : String,
                               http_aliases : Set(String)) : Bool
      actual = node
      if Noir::TreeSitter.node_type(node) == "expression_list"
        actual = first_named_child(node) || node
      end

      # http.NewServeMux() or alias.NewServeMux()
      if Noir::TreeSitter.node_type(actual) == "call_expression"
        if fn = Noir::TreeSitter.field(actual, "function")
          if Noir::TreeSitter.node_type(fn) == "selector_expression"
            operand = Noir::TreeSitter.field(fn, "operand")
            field = Noir::TreeSitter.field(fn, "field")
            if operand && field &&
               Noir::TreeSitter.node_type(operand) == "identifier" &&
               http_aliases.includes?(Noir::TreeSitter.node_text(operand, source)) &&
               Noir::TreeSitter.node_text(field, source) == "NewServeMux"
              return true
            end
          end
        end
      end

      # &http.ServeMux{}  or http.ServeMux{}  (or alias)
      txt = Noir::TreeSitter.node_text(actual, source)
      return true if http_aliases.any? { |a| txt.includes?("#{a}.ServeMux") }

      false
    end

    # Decodes a call that looks like `<recv>.HandleFunc("/p", h)` or
    # `<recv>.Handle("/p", h)` when recv is either a net/http alias or a
    # tracked serve-mux variable. Also peels one level of `NewServeMux().HandleFunc`
    # for the inline-creation pattern.
    private def decode_net_http_registration(call : LibTreeSitter::TSNode,
                                             source : String,
                                             http_aliases : Set(String),
                                             serve_mux_vars : Set(String),
                                             string_values : Hash(String, String),
                                             local_functions : Hash(String, LibTreeSitter::TSNode),
                                             local_methods : Hash(String, LibTreeSitter::TSNode),
                                             external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                             external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                             & : Route -> Nil)
      function = Noir::TreeSitter.field(call, "function")
      return unless function
      return unless Noir::TreeSitter.node_type(function) == "selector_expression"

      operand = Noir::TreeSitter.field(function, "operand")
      field = Noir::TreeSitter.field(function, "field")
      return unless operand && field

      method_name = Noir::TreeSitter.node_text(field, source)
      return unless method_name == "HandleFunc" || method_name == "Handle"

      router_name : String? = nil
      case Noir::TreeSitter.node_type(operand)
      when "identifier"
        name = Noir::TreeSitter.node_text(operand, source)
        if http_aliases.includes?(name)
          router_name = name
        elsif serve_mux_vars.includes?(name)
          router_name = name
        else
          return
        end
      when "call_expression"
        # http.NewServeMux().HandleFunc — the operand of the Handle* selector
        # is the NewServeMux() call itself. Accept only when the New call is on
        # a known http alias.
        if fn2 = Noir::TreeSitter.field(operand, "function")
          if Noir::TreeSitter.node_type(fn2) == "selector_expression"
            op2 = Noir::TreeSitter.field(fn2, "operand")
            fld2 = Noir::TreeSitter.field(fn2, "field")
            if op2 && fld2 &&
               Noir::TreeSitter.node_type(op2) == "identifier" &&
               http_aliases.includes?(Noir::TreeSitter.node_text(op2, source)) &&
               Noir::TreeSitter.node_text(fld2, source) == "NewServeMux"
              router_name = Noir::TreeSitter.node_text(op2, source)
            end
          end
        end
        return unless router_name
      else
        return
      end

      args = Noir::TreeSitter.field(call, "arguments")
      return unless args

      raw_path : String? = nil
      handler_text = ""
      handler_node : LibTreeSitter::TSNode? = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        if raw_path.nil?
          if s = string_expr_text(arg, source, string_values)
            raw_path = s
          elsif Noir::TreeSitter.node_type(arg) == "interpreted_string_literal" || Noir::TreeSitter.node_type(arg) == "raw_string_literal"
            raw_path = decode_string_literal(arg, source)
          end
        elsif handler_text.empty?
          handler_text = Noir::TreeSitter.node_text(arg, source)
          handler_node = arg
        end
      end

      return unless raw_path
      return if handler_text.empty?

      row = Noir::TreeSitter.node_start_row(call)

      # Support Go 1.22+ "METHOD /path" registration pattern.
      # When present the verb is known statically; otherwise we check
      # the handler body for method dispatch or emit ANY.
      verb = "ANY"
      path = raw_path
      if m = raw_path.match(/^([A-Z]+)\s+(.*)$/i)
        candidate_verb = m[1].upcase
        candidate_path = m[2]
        if HTTP_VERB_METHODS.includes?(candidate_verb) || candidate_verb == "ANY" || candidate_verb == "ALL"
          verb = candidate_verb
          path = candidate_path
        end
      end

      return unless path.starts_with?("/") || path.starts_with?("{$}")
      path = "/#{path}" unless path.starts_with?("/")
      path = normalize_net_http_pattern_path(path)

      if verb != "ANY"
        yield Route.new(router_name, verb, path, raw_path, handler_text, row)
        return
      end

      # For classic (verb == "ANY") registrations, inspect the handler body
      # to detect manual dispatch on r.Method (if r.Method == "QUERY",
      # switch r.Method { case http.MethodQuery: ... }, etc.).
      methods = [] of String
      if h_node = handler_node
        if body_node = find_handler_body_node(h_node, source, local_functions, local_methods)
          methods = extract_methods_from_handler_body(body_node, source)
        elsif Noir::TreeSitter.node_type(h_node) == "identifier"
          fn_name = Noir::TreeSitter.node_text(h_node, source)
          if ext_fn = external_functions[fn_name]?
            Noir::TreeSitter.parse_go(ext_fn.source) do |fn_root|
              methods = extract_methods_from_handler_body(fn_root, ext_fn.source)
            end
          end
        elsif Noir::TreeSitter.node_type(h_node) == "selector_expression"
          if field_node = Noir::TreeSitter.field(h_node, "field")
            m_name = Noir::TreeSitter.node_text(field_node, source)
            if ext_methods = external_methods[m_name]?
              ext_methods.each do |ext_m|
                Noir::TreeSitter.parse_go(ext_m.source) do |m_root|
                  methods.concat(extract_methods_from_handler_body(m_root, ext_m.source))
                end
              end
              methods.uniq!
            end
          end
        end
      end

      if methods.empty?
        yield Route.new(router_name, "ANY", path, raw_path, handler_text, row)
      else
        methods.each do |discovered_verb|
          yield Route.new(router_name, discovered_verb, path, raw_path, handler_text, row)
        end
      end
    end

    private def find_handler_body_node(handler_node : LibTreeSitter::TSNode,
                                       source : String,
                                       local_functions : Hash(String, LibTreeSitter::TSNode),
                                       local_methods : Hash(String, LibTreeSitter::TSNode)) : LibTreeSitter::TSNode?
      actual = handler_node

      # Peel wrapper calls like http.HandlerFunc(...) or middleware(...)
      while Noir::TreeSitter.node_type(actual) == "call_expression"
        if args = Noir::TreeSitter.field(actual, "arguments")
          inner = nil
          Noir::TreeSitter.each_named_child(args) do |arg|
            inner = arg
          end
          break unless inner
          actual = inner
        else
          break
        end
      end

      case Noir::TreeSitter.node_type(actual)
      when "func_literal"
        Noir::TreeSitter.field(actual, "body") || actual
      when "identifier"
        name = Noir::TreeSitter.node_text(actual, source)
        if fn_node = local_functions[name]?
          Noir::TreeSitter.field(fn_node, "body") || fn_node
        end
      when "selector_expression"
        if field = Noir::TreeSitter.field(actual, "field")
          name = Noir::TreeSitter.node_text(field, source)
          if m_node = local_methods[name]?
            Noir::TreeSitter.field(m_node, "body") || m_node
          end
        end
      end
    end

    private def extract_methods_from_handler_body(body_node : LibTreeSitter::TSNode, source : String) : Array(String)
      methods = [] of String
      method_vars = Set(String).new

      # First pass: find any local variables assigned from *.Method (e.g. `m := r.Method` or `method = r.Method`)
      walk(body_node) do |node|
        case Noir::TreeSitter.node_type(node)
        when "short_var_declaration", "assignment_statement", "var_spec"
          left = Noir::TreeSitter.field(node, "left")
          right = Noir::TreeSitter.field(node, "right")
          if Noir::TreeSitter.node_type(node) == "var_spec"
            left = Noir::TreeSitter.field(node, "name")
            right = Noir::TreeSitter.field(node, "value")
          end
          if left && right && request_method_node?(right, source)
            var_name = Noir::TreeSitter.node_text(left, source)
            method_vars << var_name unless var_name.empty?
          end
        end
      end

      # Second pass: look for `==`, `!=` comparisons and `switch` statements
      walk(body_node) do |node|
        case Noir::TreeSitter.node_type(node)
        when "binary_expression"
          op = Noir::TreeSitter.field(node, "operator")
          next unless op
          op_text = Noir::TreeSitter.node_text(op, source)
          next unless op_text == "==" || op_text == "!="

          left = Noir::TreeSitter.field(node, "left")
          right = Noir::TreeSitter.field(node, "right")
          next unless left && right

          if request_method_node?(left, source, method_vars)
            if verb = decode_http_method_node(right, source)
              methods << verb
            end
          elsif request_method_node?(right, source, method_vars)
            if verb = decode_http_method_node(left, source)
              methods << verb
            end
          end
        when "expression_switch_statement"
          val = Noir::TreeSitter.field(node, "value")
          if val && request_method_node?(val, source, method_vars)
            Noir::TreeSitter.each_named_child(node) do |case_node|
              case Noir::TreeSitter.node_type(case_node)
              when "expression_case"
                if val_list = Noir::TreeSitter.field(case_node, "value")
                  if Noir::TreeSitter.node_type(val_list) == "expression_list"
                    Noir::TreeSitter.each_named_child(val_list) do |expr|
                      if verb = decode_http_method_node(expr, source)
                        methods << verb
                      end
                    end
                  elsif verb = decode_http_method_node(val_list, source)
                    methods << verb
                  end
                else
                  Noir::TreeSitter.each_named_child(case_node) do |child|
                    if Noir::TreeSitter.node_type(child) == "expression_list"
                      Noir::TreeSitter.each_named_child(child) do |expr|
                        if verb = decode_http_method_node(expr, source)
                          methods << verb
                        end
                      end
                    elsif verb = decode_http_method_node(child, source)
                      methods << verb
                    end
                  end
                end
              end
            end
          end
        end
      end

      methods.uniq
    end

    private def request_method_node?(node : LibTreeSitter::TSNode,
                                     source : String,
                                     method_vars : Set(String) = Set(String).new) : Bool
      case Noir::TreeSitter.node_type(node)
      when "selector_expression"
        if field = Noir::TreeSitter.field(node, "field")
          Noir::TreeSitter.node_text(field, source) == "Method"
        else
          false
        end
      when "identifier"
        name = Noir::TreeSitter.node_text(node, source)
        method_vars.includes?(name) || name == "method" || name == "reqMethod"
      else
        false
      end
    end

    private def decode_http_method_node(node : LibTreeSitter::TSNode, source : String) : String?
      verb = decode_method_token(node, source)
      return verb if !verb.empty? && ALLOWED_HTTP_METHODS.includes?(verb)

      nil
    end

    # Go 1.22 ServeMux uses `{$}` as a special end-of-path wildcard.
    # `GET /{$}` matches exactly `/`, not a literal `/{ $ }` endpoint.
    private def normalize_net_http_pattern_path(path : String) : String
      return path unless path.ends_with?("{$}")

      normalized = path[0, path.size - "{$}".size]
      normalized.empty? ? "/" : normalized
    end
  end
end
