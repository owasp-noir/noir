require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Warp analyzer (tree-sitter port). Warp expresses each endpoint
  # as one `let_declaration` whose value is a chain of filter
  # combinators:
  #
  #     let get_user = warp::path("users")
  #         .and(warp::path::param::<u32>())
  #         .and(warp::path::end())
  #         .and(warp::get())
  #         .map(handler);
  #
  # The analyzer walks every `let_declaration`, inspects its value
  # subtree for the warp::* call shapes, and assembles a single
  # `Endpoint` from them.
  class Warp < RustEngine
    @external_handler_callee_cache = {} of String => Array(Noir::RustCalleeExtractor::Entry)
    @external_handler_miss_cache = Set(String).new
    @external_handler_callee_cache_mutex = Mutex.new

    def analyze
      @external_handler_callee_cache_mutex.synchronize do
        @external_handler_callee_cache.clear
        @external_handler_miss_cache.clear
      end
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        function_index = build_function_index(root, source)
        seen = Set(Int32).new
        # A composition root like `warp::path("api").and(backend(config))`
        # mounts a sibling filter-returning fn under a path prefix. Collect
        # those `{fn => prefix}` edges (and the fns that bear routes) so the
        # mounted fn's own routes pick up the prefix instead of emitting at
        # the root, and the prefix-only stub isn't emitted as a bare route.
        mounts = collect_warp_mounts(root, source)

        walk(root) do |node|
          # Two route-bearing positions: a `let route = warp::path(...)`
          # binding, and a filter-returning helper
          # `fn list() -> impl Filter { warp::path!(...).and(...) }`
          # whose tail expression IS the route (todos-style apps).
          value =
            case Noir::TreeSitter.node_type(node)
            when "let_declaration"
              Noir::TreeSitter.field(node, "value")
            when "function_item"
              function_tail_expression(node)
            end
          next unless value
          next unless warp_chain?(value, source)
          byte = LibTreeSitter.ts_node_start_byte(value).to_i
          next if seen.includes?(byte)
          seen.add(byte)

          # `warp::path("api").and(backend(config)).or(frontend())` is a
          # mount/combinator, not a leaf — its real routes live in the
          # mounted fns (emitted with the composed prefix). Skip it so we
          # don't surface a phantom `/api`.
          next if composition_root?(value, source, mounts[:route_fns])

          endpoint = build_endpoint(value, source, path, Noir::TreeSitter.node_start_row(value) + 1)
          next unless endpoint

          if include_callee
            handler_name = find_handler_name(value, source)
            if handler_name
              if handler_fn = function_for_handler(function_index, handler_name)
                attach_handler_callees(handler_fn, source, path, endpoint)
              else
                attach_external_handler_callees(handler_name, path, endpoint)
              end
            end
          end

          prefixes = enclosing_mount_prefixes(value, mounts[:mount_prefix], mounts[:fn_ranges])
          if prefixes.empty?
            endpoints << endpoint
          else
            base_url = endpoint.url
            prefixes.each do |pfx|
              ep = endpoint
              ep.url = join_paths(pfx, base_url)
              endpoints << ep
            end
          end
        end
      end

      endpoints
    end

    # A warp app composes a parent prefix onto a helper filter via
    # `warp::path("api").and(backend(config))`: the receiver carries the
    # `/api` prefix, the `.and(...)` argument is a call to a local
    # route-bearing fn (`backend`). Build `{fn => [prefix]}` (mount_prefix)
    # plus the set of route-bearing fns and every fn's byte range so the
    # emit pass can prepend the prefix to the mounted fn's own routes.
    private def collect_warp_mounts(root : LibTreeSitter::TSNode, source : String)
      fn_ranges = [] of Tuple(String, Int32, Int32)
      route_fns = Set(String).new
      mount_prefix = Hash(String, Array(String)).new

      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "function_item"
        name_node = Noir::TreeSitter.field(node, "name")
        next unless name_node
        name = Noir::TreeSitter.node_text(name_node, source)
        s = LibTreeSitter.ts_node_start_byte(node).to_i
        e = LibTreeSitter.ts_node_end_byte(node).to_i
        fn_ranges << {name, s, e}
        body = Noir::TreeSitter.field(node, "body")
        # "route-bearing" = the fn body defines a *named* path segment
        # (`warp::path("x")` / `warp::path!(..)`). A bare value-extractor
        # helper (`warp::header(..)`, `warp::path::param()`, `with_db(..)`)
        # carries no segment and must NOT be mistaken for a mountable
        # sub-router — otherwise `.and(extractor())` would suppress a real
        # leaf. `warp::path::param`/`::end` don't match `warp::path(`.
        if body
          btext = Noir::TreeSitter.node_text(body, source)
          route_fns << name if btext.includes?("warp::path(") || btext.includes?("warp::path!")
        end
      end

      walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        next unless warp_field_name(node, source) == "and"
        arg_fn = warp_mount_arg_fn(node, source)
        next unless arg_fn && route_fns.includes?(arg_fn)
        recv = warp_receiver(node)
        next unless recv
        prefix = extract_prefix_path(recv, source)
        next if prefix.empty?
        bucket = (mount_prefix[arg_fn] ||= [] of String)
        bucket << prefix unless bucket.includes?(prefix)
      end

      {route_fns: route_fns, mount_prefix: mount_prefix, fn_ranges: fn_ranges}
    end

    # True when `value` combines a local route-bearing fn via `.and(fn())`
    # / `.or(fn())` — i.e. it's a router composition, not a leaf endpoint.
    private def composition_root?(value : LibTreeSitter::TSNode, source : String, route_fns : Set(String)) : Bool
      found = false
      walk(value) do |node|
        next if found
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        name = warp_field_name(node, source)
        next unless name == "and" || name == "or"
        arg_fn = warp_mount_arg_fn(node, source)
        found = true if arg_fn && route_fns.includes?(arg_fn)
      end
      found
    end

    # The mount prefix(es) for the smallest enclosing fn of `value`, if that
    # fn is mounted under a parent path elsewhere; `[]` otherwise.
    private def enclosing_mount_prefixes(value : LibTreeSitter::TSNode,
                                         mount_prefix : Hash(String, Array(String)),
                                         fn_ranges : Array(Tuple(String, Int32, Int32))) : Array(String)
      return [] of String if mount_prefix.empty?
      vb = LibTreeSitter.ts_node_start_byte(value).to_i
      best : String? = nil
      best_size = Int32::MAX
      fn_ranges.each do |name, s, e|
        next unless mount_prefix.has_key?(name)
        next unless vb >= s && vb < e
        size = e - s
        if size < best_size
          best_size = size
          best = name
        end
      end
      best ? mount_prefix[best] : [] of String
    end

    private def warp_field_name(call : LibTreeSitter::TSNode, source : String) : String?
      fn = Noir::TreeSitter.field(call, "function")
      return unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
      field = Noir::TreeSitter.field(fn, "field")
      field ? Noir::TreeSitter.node_text(field, source) : nil
    end

    private def warp_receiver(call : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      fn = Noir::TreeSitter.field(call, "function")
      return unless fn && Noir::TreeSitter.node_type(fn) == "field_expression"
      Noir::TreeSitter.field(fn, "value")
    end

    # First positional argument of a `.and(...)` call when it is a plain
    # local fn call (`backend(config)`), returning the fn name. Scoped
    # filters (`warp::ws()`) and method calls (`state.clone()`) are not
    # local fns and return `nil`.
    private def warp_mount_arg_fn(call : LibTreeSitter::TSNode, source : String) : String?
      args = Noir::TreeSitter.field(call, "arguments")
      return unless args
      result : String? = nil
      Noir::TreeSitter.each_named_child(args) do |arg|
        next if result
        next unless Noir::TreeSitter.node_type(arg) == "call_expression"
        f = Noir::TreeSitter.field(arg, "function")
        if f && Noir::TreeSitter.node_type(f) == "identifier"
          result = Noir::TreeSitter.node_text(f, source)
        end
      end
      result
    end

    # Collect the leading path segments of a filter chain (a `.and(fn())`
    # receiver) into a `/a/b` prefix. Only `warp::path(..)` / `path!(..)`
    # contribute; verbs and value extractors are ignored.
    private def extract_prefix_path(node : LibTreeSitter::TSNode, source : String) : String
      parts = [] of String
      discard = [] of Param
      walk(node) do |n|
        case Noir::TreeSitter.node_type(n)
        when "macro_invocation"
          parse_path_macro(n, source, parts, discard) if path_macro?(n, source)
        when "call_expression"
          if call_function_text(n, source) == "warp::path"
            text = first_string_literal_text(Noir::TreeSitter.field(n, "arguments"), source)
            parts << text if text
          end
        end
      end
      parts.empty? ? "" : "/" + parts.join("/")
    end

    private def join_paths(prefix : String, route : String) : String
      return route if prefix.empty?
      return prefix if route.empty? || route == "/"
      "#{prefix.rstrip('/')}/#{route.lstrip('/')}"
    end

    private def warp_chain?(value : LibTreeSitter::TSNode, source : String) : Bool
      found = false
      walk(value) do |node|
        next if found
        if Noir::TreeSitter.node_type(node) == "scoped_identifier"
          text = Noir::TreeSitter.node_text(node, source)
          found = true if text.starts_with?("warp::")
        end
      end
      found
    end

    # Walk the value subtree once, gathering enough state to build
    # the endpoint: method, ordered path parts, params.
    private def build_endpoint(value : LibTreeSitter::TSNode,
                               source : String,
                               file_path : String,
                               row : Int32) : Endpoint?
      method = "GET"
      path_parts = [] of String
      params = [] of Param
      param_count = 0
      has_path_end = false

      walk(value) do |node|
        case Noir::TreeSitter.node_type(node)
        when "macro_invocation"
          # `warp::path!("todos" / u64 / "items")` — the idiomatic
          # multi-segment form. tree-sitter leaves the args as a flat
          # `token_tree`; string literals are path segments and type
          # tokens (`u64`, `String`, `Uuid`, …) are path params.
          if path_macro?(node, source)
            seg_count = parse_path_macro(node, source, path_parts, params)
            has_path_end = true if seg_count > 0
          end
        when "call_expression"
          fn_text = call_function_text(node, source)
          next unless fn_text

          case fn_text
          when "warp::get"     then method = "GET"
          when "warp::post"    then method = "POST"
          when "warp::put"     then method = "PUT"
          when "warp::delete"  then method = "DELETE"
          when "warp::patch"   then method = "PATCH"
          when "warp::head"    then method = "HEAD"
          when "warp::options" then method = "OPTIONS"
          when "warp::path"
            text = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
            path_parts << text if text
          when "warp::path::end"
            has_path_end = true
          end
        when "generic_function"
          fn_text = call_function_text_from_generic(node, source)
          next unless fn_text

          if fn_text == "warp::query"
            type_name = first_type_argument(node, source) || "query"
            params << Param.new(type_name, "", "query") unless params.any? { |p| p.name == type_name && p.param_type == "query" }
          elsif fn_text == "warp::body::json"
            type_name = first_type_argument(node, source) || "body"
            params << Param.new(type_name, "", "json") unless params.any? { |p| p.name == type_name && p.param_type == "json" }
          elsif fn_text == "warp::body::form"
            type_name = first_type_argument(node, source) || "body"
            params << Param.new(type_name, "", "form") unless params.any? { |p| p.name == type_name && p.param_type == "form" }
          end
        when "scoped_identifier"
          text = Noir::TreeSitter.node_text(node, source)
          if text == "warp::path::param"
            param_count += 1
          end
        end
      end

      # Walk again for warp::header(...) / warp::cookie(...) names —
      # the call_expression's function side may be a `generic_function`
      # (turbofish present) or a plain `scoped_identifier`.
      walk(value) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        fn_text = call_function_text(node, source) || call_function_text_from_generic_call(node, source)
        next unless fn_text

        case fn_text
        when "warp::header"
          name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
          params << Param.new(name, "", "header") if name && !params.any? { |p| p.name == name && p.param_type == "header" }
        when "warp::cookie"
          name = first_string_literal_text(Noir::TreeSitter.field(node, "arguments"), source)
          params << Param.new(name, "", "cookie") if name && !params.any? { |p| p.name == name && p.param_type == "cookie" }
        end
      end

      param_count.times do |i|
        name = param_count > 1 ? "param#{i + 1}" : "param"
        path_parts << ":#{name}"
        params << Param.new(name, "", "path")
      end

      return if path_parts.empty? && !has_path_end

      route = path_parts.empty? ? "/" : "/" + path_parts.join("/")
      details = Details.new(PathInfo.new(file_path, row))
      Endpoint.new(route, method, params, details)
    end

    # The trailing (no-semicolon) expression of a function body block —
    # the value the function returns. Returns `nil` when the function
    # ends in a statement (so we don't treat `warp::serve(...).run()` and
    # other side-effecting tails as routes; the empty-path guard in
    # build_endpoint also filters those, but this keeps the walk tight).
    private def function_tail_expression(function : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      body = Noir::TreeSitter.field(function, "body")
      return unless body && Noir::TreeSitter.node_type(body) == "block"
      tail = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.each_named_child(body) do |child|
        case Noir::TreeSitter.node_type(child)
        when "line_comment", "block_comment"
          # skip
        else
          tail = child
        end
      end
      return unless tail
      case Noir::TreeSitter.node_type(tail)
      when "expression_statement", "let_declaration", "empty_statement"
        nil
      else
        tail
      end
    end

    # True when `node` is a `warp::path!(...)` / `path!(...)` macro.
    private def path_macro?(node : LibTreeSitter::TSNode, source : String) : Bool
      macro_node = Noir::TreeSitter.field(node, "macro")
      return false unless macro_node
      name = Noir::TreeSitter.node_text(macro_node, source).split("::").last
      name == "path"
    end

    # Parse a `path!("a" / u64 / "b")` token tree, appending each string
    # literal as a path segment and each type token as a `:param`
    # placeholder. Returns the number of components appended. Param
    # names follow the warp convention: a lone param is `param`, several
    # become `param1`, `param2`, … .
    private def parse_path_macro(node : LibTreeSitter::TSNode,
                                 source : String,
                                 path_parts : Array(String),
                                 params : Array(Param)) : Int32
      tt = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.each_named_child(node) do |child|
        tt = child if Noir::TreeSitter.node_type(child) == "token_tree"
      end
      return 0 unless token_tree = tt

      type_total = 0
      Noir::TreeSitter.each_named_child(token_tree) do |child|
        case Noir::TreeSitter.node_type(child)
        when "primitive_type", "type_identifier", "scoped_type_identifier", "generic_type", "identifier"
          type_total += 1
        end
      end

      count = 0
      type_idx = 0
      Noir::TreeSitter.each_named_child(token_tree) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_literal"
          seg = string_content_text(child, source)
          if seg && !seg.empty?
            path_parts << seg
            count += 1
          end
        when "primitive_type", "type_identifier", "scoped_type_identifier", "generic_type", "identifier"
          # `warp::path!("socket" / String)` — inside a macro `token_tree`
          # the grammar has no type context, so a non-primitive type like
          # `String` / `Uuid` / a custom id type parses as a bare
          # `identifier` rather than `type_identifier`. warp's `path!`
          # only accepts string-literal segments and type params, so any
          # top-level identifier here is a path param (`/{param}`).
          type_idx += 1
          name = type_total > 1 ? "param#{type_idx}" : "param"
          path_parts << ":#{name}"
          params << Param.new(name, "", "path") unless params.any? { |p| p.name == name && p.param_type == "path" }
          count += 1
        end
      end
      count
    end

    private def string_content_text(string_literal : LibTreeSitter::TSNode, source : String) : String?
      Noir::TreeSitter.each_named_child(string_literal) do |grand|
        return Noir::TreeSitter.node_text(grand, source) if Noir::TreeSitter.node_type(grand) == "string_content"
      end
      nil
    end

    # `.map(handler)` / `.and_then(handler)` / `.then(handler)` — pull
    # the handler identifier (or trailing segment of a scoped path).
    private def find_handler_name(value : LibTreeSitter::TSNode, source : String) : String?
      found : String? = nil
      walk(value) do |node|
        next if found
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        fn_node = Noir::TreeSitter.field(node, "function")
        next unless fn_node && Noir::TreeSitter.node_type(fn_node) == "field_expression"
        field = Noir::TreeSitter.field(fn_node, "field")
        next unless field
        method = Noir::TreeSitter.node_text(field, source)
        next unless method == "map" || method == "and_then" || method == "then"

        args = Noir::TreeSitter.field(node, "arguments")
        next unless args
        Noir::TreeSitter.each_named_child(args) do |arg|
          case Noir::TreeSitter.node_type(arg)
          when "identifier"
            found = Noir::TreeSitter.node_text(arg, source)
          when "scoped_identifier"
            found = Noir::TreeSitter.node_text(arg, source)
          when "generic_function"
            # `handlers::generic_handler::<u32>` — peel the turbofish.
            inner = Noir::TreeSitter.field(arg, "function")
            if inner
              found = Noir::TreeSitter.node_text(inner, source)
            end
          end
          break if found
        end
      end
      found
    end

    private def function_for_handler(index : Hash(String, LibTreeSitter::TSNode), handler_name : String) : LibTreeSitter::TSNode?
      leaf = handler_name.split("::").last
      index[handler_name]? || index[leaf]?
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

    private def attach_external_handler_callees(handler_name : String,
                                                current_path : String,
                                                endpoint : Endpoint)
      parts = handler_name.split("::").reject(&.empty?)
      return if parts.size < 2

      function_name = parts.last
      module_parts = parts[0...-1]

      candidate_module_paths(current_path, module_parts).each do |candidate|
        next unless File.exists?(candidate)

        if entries = cached_external_handler_callees(candidate, function_name)
          attach_rust_callees(endpoint, entries)
          return
        end
      end
    end

    private def cached_external_handler_callees(candidate : String,
                                                function_name : String) : Array(Noir::RustCalleeExtractor::Entry)?
      cache_key = "#{candidate}\0#{function_name}"

      @external_handler_callee_cache_mutex.synchronize do
        return @external_handler_callee_cache[cache_key]? if @external_handler_callee_cache.has_key?(cache_key)
        return if @external_handler_miss_cache.includes?(cache_key)

        entries = parse_external_handler_callees(candidate, function_name)
        if entries
          @external_handler_callee_cache[cache_key] = entries
        else
          @external_handler_miss_cache.add(cache_key)
        end
        entries
      end
    end

    private def parse_external_handler_callees(candidate : String,
                                               function_name : String) : Array(Noir::RustCalleeExtractor::Entry)?
      source = read_file_content(candidate)
      entries = nil.as(Array(Noir::RustCalleeExtractor::Entry)?)

      Noir::TreeSitter.parse_rust(source) do |root|
        index = build_function_index(root, source)
        if function = index[function_name]?
          body = Noir::TreeSitter.field(function, "body")
          entries = body ? Noir::RustCalleeExtractorTS.callees_in_body(body, source, candidate) : [] of Noir::RustCalleeExtractor::Entry
        end
      end

      entries
    end

    private def candidate_module_paths(current_path : String, module_parts : Array(String)) : Array(String)
      return [] of String if module_parts.empty?

      base_dir, parts = module_base_dir(current_path, module_parts)
      return [] of String if parts.empty?

      module_path = parts.join("/")
      [
        File.join(base_dir, "#{module_path}.rs"),
        File.join(base_dir, module_path, "mod.rs"),
      ]
    end

    private def module_base_dir(current_path : String, module_parts : Array(String)) : Tuple(String, Array(String))
      first = module_parts.first
      rest = module_parts[1..]? || [] of String

      case first
      when "crate"
        {crate_src_dir(current_path), rest}
      when "self"
        {current_module_dir(current_path), rest}
      when "super"
        {File.dirname(current_module_dir(current_path)), rest}
      else
        {current_module_dir(current_path), module_parts}
      end
    end

    private def current_module_dir(current_path : String) : String
      File.dirname(current_path)
    end

    private def crate_src_dir(current_path : String) : String
      marker = "/src/"
      if idx = current_path.rindex(marker)
        current_path[0, idx + marker.size - 1]
      else
        File.dirname(current_path)
      end
    end

    private def call_function_text(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node
      case Noir::TreeSitter.node_type(fn_node)
      when "scoped_identifier"
        Noir::TreeSitter.node_text(fn_node, source)
      end
    end

    # `foo::<T>` — when a call_expression's function is a
    # `generic_function`, peel one level to find the underlying
    # scoped_identifier / identifier.
    private def call_function_text_from_generic_call(call : LibTreeSitter::TSNode, source : String) : String?
      fn_node = Noir::TreeSitter.field(call, "function")
      return unless fn_node && Noir::TreeSitter.node_type(fn_node) == "generic_function"
      call_function_text_from_generic(fn_node, source)
    end

    private def call_function_text_from_generic(generic : LibTreeSitter::TSNode, source : String) : String?
      inner = Noir::TreeSitter.field(generic, "function")
      return unless inner
      Noir::TreeSitter.node_text(inner, source)
    end

    # `warp::query::<SearchQuery>()` → "SearchQuery". Walks the
    # `type_arguments` field for the first type_identifier and returns
    # its text.
    private def first_type_argument(generic : LibTreeSitter::TSNode, source : String) : String?
      type_args = Noir::TreeSitter.field(generic, "type_arguments")
      return unless type_args
      result : String? = nil
      walk(type_args) do |child|
        next if result
        case Noir::TreeSitter.node_type(child)
        when "type_identifier", "primitive_type"
          result = Noir::TreeSitter.node_text(child, source)
        when "scoped_type_identifier"
          result = Noir::TreeSitter.node_text(child, source).split("::").last
        end
      end
      result
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
