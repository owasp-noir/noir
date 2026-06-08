require "../../engines/rust_engine"
require "../../../ext/tree_sitter/tree_sitter"
require "../../../miniparsers/rust_callee_extractor_ts"

module Analyzer::Rust
  # Rocket analyzer (tree-sitter port). Rocket attaches routes via
  # `#[get("/x")]` / `#[post("/x", data = "<body>")]` outer attribute
  # macros. tree-sitter-rust leaves macro argument lists as
  # `token_tree`, but the lexer still tags `string_literal` /
  # `identifier` children inside — we walk those for the route path,
  # the `data = "<...>"` form, query / path angle-bracket params, and
  # `CookieJar` / `headers().get(...)` body uses.
  class Rocket < RustEngine
    HTTP_VERBS = Set{"get", "post", "put", "delete", "patch", "head", "options"}
    alias ScopedRouteKey = Tuple(String, String, String)
    alias AliasKey = Tuple(String, String)
    alias RouteLeaf = Tuple(String, String?)
    alias MountEntry = Tuple(String, Symbol, Array(RouteLeaf), String?, String, String)

    # Cross-file `.mount()` prefix composition. A Rocket handler's real URL
    # is its `#[get("/x")]` attribute path prefixed by the base it is mounted
    # under — but the `.mount("/api", routes![...])` call lives in `main.rs`
    # while the handler lives in another module, so the per-file pass emits
    # `/x` instead of `/api/x`. `analyze` walks the project once up front to
    # build a `{base_path, module, handler_leaf} => [prefix]` index, resolving:
    #   * direct `.mount("/p", routes![a, mod::b])`,
    #   * `.mount(prefix, route_fn())` where `route_fn` returns `routes![...]`
    #     (and recursively `routes.append(&mut submod::routes())`),
    #   * `use path::routes as alias;` re-export aliases,
    #   * array-concat prefixes (`[basepath, "/api"].concat()`).
    # Each leaf is tagged with the module of the `routes!` it appears in
    # (or the ref's own module when qualified) so a handler only inherits a
    # prefix when it lives in the registering module — names shared across
    # modules never cross-contaminate.
    @mount_index : Hash(ScopedRouteKey, Array(String))? = nil

    def analyze
      @mount_index = build_mount_index
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      source = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      Noir::TreeSitter.parse_rust(source) do |root|
        each_routing_pair(root) do |attr, function|
          route = extract_route(attr, source)
          next unless route
          route_path, method, data_param, attr_row = route

          # Rocket route attributes carry their query params inline
          # (`/path?<q>&<limit>`) and bracket their path params
          # (`/with-param/<id>`). The query spec gets parsed into
          # actual params in `extract_params` below, but the URL we
          # ship out should be the canonical bare path with `{name}`
          # placeholders — strip the `?...` suffix and convert
          # `<name>` → `{name}` so output matches every other
          # framework's path shape.
          canonical_path = canonicalize_rocket_path(route_path)

          # Resolve the `.mount("/base", ...)` prefix(es) this handler is
          # registered under (cross-file). A handler mounted at several
          # bases (or at none) emits one endpoint per resolved URL.
          handler_leaf = rocket_function_name(function, source)
          prefixes = handler_leaf ? lookup_mount_prefixes(handler_leaf, path) : nil
          urls = if prefixes && !prefixes.empty?
                   prefixes.map { |pfx| join_mount_path(pfx, canonical_path) }
                 else
                   [canonical_path]
                 end

          urls.each do |url|
            details = Details.new(PathInfo.new(path, attr_row))
            params = extract_params(route_path, data_param)
            endpoint = Endpoint.new(url, method, params, details)

            extract_function_extras(function, source, endpoint)
            attach_handler_callees(function, source, path, endpoint) if include_callee

            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    # ── cross-file `.mount()` prefix index ───────────────────────────

    # Walk the whole project once, gathering `use ... as alias;` re-exports,
    # every `fn routes()`-style route collector's leaves + sub-collector
    # calls, and every `.mount(prefix, ...)`. Resolve them into a
    # `{base_path, module, handler_leaf} => [prefix]` index.
    private def build_mount_index : Hash(ScopedRouteKey, Array(String))
      alias_map = {} of AliasKey => String
      fn_leaves = {} of ScopedRouteKey => Array(RouteLeaf)
      fn_appends = {} of ScopedRouteKey => Array(String)
      mounts = [] of MountEntry

      all_files.each do |path|
        next if File.directory?(path)
        next unless File.exists?(path) && File.extname(path) == ".rs"
        next if RustEngine.test_path?(path)
        base = configured_base_for(path)
        src = read_file_content(path)
        next unless src.includes?("routes!") || src.includes?(".mount(") || src.includes?("routes as")
        file_mod = primary_module(path)
        begin
          test_regions = RustEngine.collect_cfg_test_regions(src)
          Noir::TreeSitter.parse_rust(src) do |root|
            collect_use_aliases(root, src, base, alias_map)
            collect_route_fns(root, src, base, file_mod, test_regions, fn_leaves, fn_appends)
            collect_mounts(root, src, base, file_mod, test_regions, mounts)
          end
        rescue e
          logger.debug "rocket mount-index scan error #{path}: #{e}"
        end
      end

      index = {} of ScopedRouteKey => Array(String)
      mounts.each do |prefix, kind, list_leaves, call_ref, base, file_mod|
        leaves =
          if kind == :list
            list_leaves
          else
            resolved = [] of RouteLeaf
            if cr = call_ref
              resolve_route_fn(cr, base, alias_map, fn_leaves, fn_appends, Set(ScopedRouteKey).new, resolved)
            end
            resolved
          end
        leaves.each do |leaf, mod_opt|
          key = {base, mod_opt || file_mod, leaf}
          bucket = (index[key] ||= [] of String)
          bucket << prefix unless bucket.includes?(prefix)
        end
      end
      index
    end

    # `core::routes as core_routes` -> alias_map["core_routes"] = "core::routes"
    # (last two segments of the re-export path).
    private def collect_use_aliases(node : LibTreeSitter::TSNode, source : String, base : String, alias_map : Hash(AliasKey, String))
      walk(node) do |n|
        next unless Noir::TreeSitter.node_type(n) == "use_as_clause"
        path = Noir::TreeSitter.field(n, "path")
        ali = Noir::TreeSitter.field(n, "alias")
        next unless path && ali
        segs = Noir::TreeSitter.node_text(path, source).split("::")
        target = segs.size >= 2 ? "#{segs[-2]}::#{segs[-1]}" : segs[-1]
        alias_map[{base, Noir::TreeSitter.node_text(ali, source)}] = target
      end
    end

    # Record every fn whose body builds a route list: its `routes![...]`
    # leaves (keyed `module::fnname`) and any `submod::routes()` sub-collector
    # calls (for the `routes.append(&mut submod::routes())` aggregation form).
    private def collect_route_fns(node : LibTreeSitter::TSNode, source : String,
                                  base : String,
                                  file_mod : String, test_regions : Array(Tuple(Int32, Int32)),
                                  fn_leaves : Hash(ScopedRouteKey, Array(RouteLeaf)),
                                  fn_appends : Hash(ScopedRouteKey, Array(String)))
      walk(node) do |n|
        next unless Noir::TreeSitter.node_type(n) == "function_item"
        next if RustEngine.inside_test_region?(n, test_regions)
        name_node = Noir::TreeSitter.field(n, "name")
        body = Noir::TreeSitter.field(n, "body")
        next unless name_node && body

        leaves = [] of RouteLeaf
        appends = [] of String
        walk(body) do |b|
          case Noir::TreeSitter.node_type(b)
          when "macro_invocation"
            collect_routes_macro_leaves(b, source, leaves)
          when "call_expression"
            # `routes.append(&mut submod::routes())` (scoped) and the
            # `r.append(&mut aliased_routes())` (bare, resolved via a
            # `use ... as` alias) sub-collector forms. Non-route calls are
            # filtered out at resolution time (resolve_fn_key returns nil).
            cfn = Noir::TreeSitter.field(b, "function")
            appends << Noir::TreeSitter.node_text(cfn, source) if cfn && {"scoped_identifier", "identifier"}.includes?(Noir::TreeSitter.node_type(cfn))
          end
        end
        next if leaves.empty? && appends.empty?
        key = {base, file_mod, Noir::TreeSitter.node_text(name_node, source)}
        fn_leaves[key] = leaves
        fn_appends[key] = appends
      end
    end

    # Find every `.mount(prefix, arg)` call and record it as either a direct
    # `routes![...]` leaf list or a deferred route-collector call to resolve.
    private def collect_mounts(node : LibTreeSitter::TSNode, source : String,
                               base : String, file_mod : String, test_regions : Array(Tuple(Int32, Int32)),
                               mounts : Array(MountEntry))
      walk(node) do |n|
        next unless Noir::TreeSitter.node_type(n) == "call_expression"
        next if RustEngine.inside_test_region?(n, test_regions)
        fnf = Noir::TreeSitter.field(n, "function")
        next unless fnf && Noir::TreeSitter.node_type(fnf) == "field_expression"
        fld = Noir::TreeSitter.field(fnf, "field")
        next unless fld && Noir::TreeSitter.node_text(fld, source) == "mount"
        args = Noir::TreeSitter.field(n, "arguments")
        next unless args
        named = [] of LibTreeSitter::TSNode
        Noir::TreeSitter.each_named_child(args) { |c| named << c }
        next if named.size < 2

        prefix = extract_mount_prefix(named[0], source)
        next unless prefix
        arg = named[1]
        case Noir::TreeSitter.node_type(arg)
        when "macro_invocation"
          leaves = [] of RouteLeaf
          collect_routes_macro_leaves(arg, source, leaves)
          mounts << {prefix, :list, leaves, nil, base, file_mod} unless leaves.empty?
        when "call_expression"
          cfn = Noir::TreeSitter.field(arg, "function")
          if cfn && {"scoped_identifier", "identifier"}.includes?(Noir::TreeSitter.node_type(cfn))
            mounts << {prefix, :call, [] of RouteLeaf, Noir::TreeSitter.node_text(cfn, source), base, file_mod}
          end
        when "identifier"
          mounts << {prefix, :call, [] of RouteLeaf, Noir::TreeSitter.node_text(arg, source), base, file_mod}
        end
      end
    end

    # Pull handler leaves out of a `routes![a, mod::b, x::y::z]` macro. The
    # macro body is a flat `token_tree` (scoped paths are NOT single nodes),
    # so we parse the token-tree text: split on commas, take each item's
    # path, and tag the leaf with the segment before it (its module) when
    # the ref is qualified.
    private def collect_routes_macro_leaves(macro_node : LibTreeSitter::TSNode, source : String,
                                            leaves : Array(RouteLeaf))
      mname = Noir::TreeSitter.field(macro_node, "macro")
      return unless mname && Noir::TreeSitter.node_text(mname, source).split("::").last == "routes"
      token_tree = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.each_named_child(macro_node) do |child|
        token_tree = child if Noir::TreeSitter.node_type(child) == "token_tree"
      end
      return unless tt = token_tree
      parse_routes_list(Noir::TreeSitter.node_text(tt, source), leaves)
    end

    private def parse_routes_list(text : String, leaves : Array(RouteLeaf))
      inner = text.strip
      inner = inner[1..] if inner.starts_with?('[') || inner.starts_with?('(')
      inner = inner[0...-1] if inner.ends_with?(']') || inner.ends_with?(')')
      inner = inner.gsub(/\/\/[^\n]*/, " ").gsub(%r{/\*.*?\*/}m, " ")
      inner.split(',').each do |raw|
        m = raw.match(/([A-Za-z_]\w*(?:\s*::\s*[A-Za-z_]\w*)*)/)
        next unless m
        segs = m[1].split("::").map(&.strip)
        next if segs.empty?
        leaves << {segs[-1], segs.size >= 2 ? segs[-2] : nil}
      end
    end

    # Resolve a route-collector ref (`api::core_routes`, `accounts::routes`,
    # a `routes_var`) to its handler leaves, following `use ... as` aliases
    # and recursing through `routes.append(&mut submod::routes())`. Each leaf
    # is tagged with the collector fn's module (or the ref's own module when
    # the `routes![...]` entry was qualified).
    private def resolve_route_fn(ref : String, base : String, alias_map : Hash(AliasKey, String),
                                 fn_leaves : Hash(ScopedRouteKey, Array(RouteLeaf)),
                                 fn_appends : Hash(ScopedRouteKey, Array(String)),
                                 visited : Set(ScopedRouteKey), acc : Array(RouteLeaf))
      key = resolve_fn_key(ref, base, alias_map, fn_leaves)
      return unless key
      return if visited.includes?(key)
      visited.add(key)
      fn_mod = key[1]
      if leaves = fn_leaves[key]?
        leaves.each { |leaf, mod_opt| acc << {leaf, mod_opt || fn_mod} }
      end
      if appends = fn_appends[key]?
        appends.each { |aref| resolve_route_fn(aref, base, alias_map, fn_leaves, fn_appends, visited, acc) }
      end
    end

    private def resolve_fn_key(ref : String, base : String, alias_map : Hash(AliasKey, String),
                               fn_leaves : Hash(ScopedRouteKey, Array(RouteLeaf))) : ScopedRouteKey?
      leaf = ref.split("::").last
      if target = alias_map[{base, leaf}]?
        tsegs = target.split("::")
        if tsegs.size >= 2
          target_key = {base, tsegs[-2], tsegs[-1]}
          return target_key if fn_leaves.has_key?(target_key)
        end
        # A re-export written inside a nested `use a::{ b as c }` group records
        # the alias target relative to that group (`events_routes`, not
        # `core::events_routes`), so it won't be a registry key directly —
        # match it as a unique module-qualified suffix instead.
        tleaf = target.split("::").last
        tmatches = fn_leaves.keys.select { |key| key[0] == base && key[2] == tleaf }
        return tmatches.first if tmatches.size == 1
      end
      segs = ref.split("::")
      if segs.size >= 2
        cand = {base, segs[-2], segs[-1]}
        return cand if fn_leaves.has_key?(cand)
      end
      matches = fn_leaves.keys.select { |key| key[0] == base && key[2] == leaf }
      matches.size == 1 ? matches.first : nil
    end

    # `.mount("/api", ...)` / `.mount([basepath, "/api"].concat(), ...)` /
    # `.mount(format-free array forms, ...)` → the literal prefix. Non-literal
    # segments (a `basepath` config var) contribute nothing; the literal parts
    # are joined, matching Rocket's runtime concatenation for the common
    # empty-base default.
    private def extract_mount_prefix(node : LibTreeSitter::TSNode, source : String) : String?
      case Noir::TreeSitter.node_type(node)
      when "string_literal", "raw_string_literal"
        string_content(node, source)
      when "array_expression"
        parts = [] of String
        Noir::TreeSitter.each_named_child(node) do |el|
          if {"string_literal", "raw_string_literal"}.includes?(Noir::TreeSitter.node_type(el))
            if s = string_content(el, source)
              parts << s
            end
          end
        end
        parts.empty? ? nil : parts.join
      when "call_expression"
        fnf = Noir::TreeSitter.field(node, "function")
        return unless fnf && Noir::TreeSitter.node_type(fnf) == "field_expression"
        fld = Noir::TreeSitter.field(fnf, "field")
        return unless fld && {"concat", "join", "to_string", "to_owned", "into"}.includes?(Noir::TreeSitter.node_text(fld, source))
        recv = Noir::TreeSitter.field(fnf, "value")
        recv ? extract_mount_prefix(recv, source) : nil
      end
    end

    private def rocket_function_name(function : LibTreeSitter::TSNode, source : String) : String?
      name = Noir::TreeSitter.field(function, "name")
      name ? Noir::TreeSitter.node_text(name, source) : nil
    end

    # Canonical single module a `.rs` file is referred to by. A plain
    # `foo.rs` is module `foo`; `foo/mod.rs` is module `foo`. A crate root
    # (`src/main.rs` / `src/lib.rs`) has no module name of its own, so we key
    # it by the crate directory — this keeps the identically named
    # `examples/<x>/src/main.rs` roots of a framework example monorepo apart
    # instead of collapsing them all to a shared `src` pseudo-module.
    private def primary_module(path : String) : String
      base = File.basename(path, ".rs")
      dir = File.dirname(path)
      case base
      when "mod"
        File.basename(dir)
      when "lib", "main"
        parent = File.basename(dir)
        parent == "src" ? File.basename(File.dirname(dir)) : parent
      else
        base
      end
    end

    # Mount prefix(es) for a handler, matched module-aware so a leaf shared
    # across modules only inherits the prefix of the module that registers
    # it. nil when the handler isn't mounted anywhere visible.
    private def lookup_mount_prefixes(leaf : String, file_path : String) : Array(String)?
      index = @mount_index
      return unless index
      if prefixes = index[{configured_base_for(file_path), primary_module(file_path), leaf}]?
        return prefixes
      end
      nil
    end

    private def join_mount_path(prefix : String, path : String) : String
      pfx = (prefix.starts_with?("/") ? prefix : "/#{prefix}").rstrip("/")
      return path.starts_with?("/") ? path : "/#{path}" if pfx.empty?
      suffix = path.lstrip("/")
      suffix.empty? ? pfx : "#{pfx}/#{suffix}"
    end

    # `#[get("/x")]` / `#[post("/x", data = "<body>")]` →
    # `{route, METHOD, data_var?, attr_row_1based}`. Returns `nil` for
    # non-routing attributes.
    private def extract_route(attr_item : LibTreeSitter::TSNode,
                              source : String) : Tuple(String, String, String?, Int32)?
      attr = find_named_child(attr_item, "attribute")
      return unless attr

      attr_name = nil.as(String?)
      Noir::TreeSitter.each_named_child(attr) do |child|
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          attr_name = Noir::TreeSitter.node_text(child, source).downcase
          break
        end
      end
      return unless attr_name

      arguments = Noir::TreeSitter.field(attr, "arguments")
      return unless arguments

      verb =
        if HTTP_VERBS.includes?(attr_name)
          attr_name
        elsif attr_name == "route"
          # Generic `#[route(GET, uri = "/p")]` / `#[route("/p",
          # method = GET)]`. Only standard HTTP verbs are emitted; custom
          # WebDAV-style methods (PROPFIND, VERSION-CONTROL) are skipped.
          http_verb_in_token_tree(arguments, source)
        end
      return unless verb

      route_path, data_param = parse_token_tree(arguments, source)
      return unless route_path
      {route_path, verb.upcase, data_param, Noir::TreeSitter.node_start_row(attr_item) + 1}
    end

    # Walk the attribute's token_tree once. First `string_literal` is
    # the route path. Any `identifier "data"` followed by a
    # `string_literal` yields the data parameter variable name (the
    # `<input>` form). Other keyword args are ignored — rocket's
    # `format = "..."` / `rank = N` aren't endpoint-shaping.
    private def parse_token_tree(token_tree : LibTreeSitter::TSNode,
                                 source : String) : Tuple(String?, String?)
      route_path : String? = nil
      data_param : String? = nil
      saw_data = false

      Noir::TreeSitter.each_named_child(token_tree) do |child|
        case Noir::TreeSitter.node_type(child)
        when "string_literal"
          text = string_content(child, source)
          if route_path.nil?
            route_path = text
          elsif saw_data && data_param.nil?
            # `data = "<input>"` — strip the angle brackets.
            data_param = strip_angle_brackets(text) if text
            saw_data = false
          end
        when "identifier"
          saw_data = true if Noir::TreeSitter.node_text(child, source) == "data"
        end
      end

      {route_path, data_param}
    end

    # Find the first HTTP verb in a `#[route(...)]` argument list — the
    # leading `GET` of the legacy form or the `method = GET` value of the
    # modern form. Checks identifiers and verb-valued string literals;
    # returns the lowercased verb or nil (custom non-HTTP methods skipped).
    private def http_verb_in_token_tree(arguments : LibTreeSitter::TSNode, source : String) : String?
      result : String? = nil
      Noir::TreeSitter.each_named_child(arguments) do |child|
        next if result
        case Noir::TreeSitter.node_type(child)
        when "identifier", "scoped_identifier"
          v = Noir::TreeSitter.node_text(child, source).split("::").last.downcase
          result = v if HTTP_VERBS.includes?(v)
        when "string_literal"
          if (s = string_content(child, source)) && HTTP_VERBS.includes?(s.downcase)
            result = s.downcase
          end
        end
      end
      result
    end

    private def strip_angle_brackets(value : String?) : String?
      return unless value
      if value.starts_with?('<') && value.ends_with?('>')
        value[1..-2]
      else
        value
      end
    end

    # `/users/<id>` / `/search?<q>&<limit>` / `data = "<body>"` get
    # rolled together here so the legacy spec's param ordering stays
    # stable.
    # `/path/<id>?<q>&<limit>` → `/path/{id}`. Strips the inline
    # query-spec suffix Rocket attributes use to declare query
    # params and converts the `<name>` path bracket form to the
    # canonical `{name}` placeholder. Trailing `..` segments
    # (`<page..>`) drop the trailing dots so the placeholder is
    # the bare identifier.
    private def canonicalize_rocket_path(route : String) : String
      path_part = route.split("?", 2)[0]
      path_part.gsub(/<([^>]+)>/) do |_|
        name = $1.split("..").first.strip
        "{#{name}}"
      end
    end

    private def extract_params(route : String, data_param : String?) : Array(Param)
      params = [] of Param

      parts = route.split("?", 2)
      path_part = parts[0]
      query_part = parts[1]?

      # Tolerate the trailing-segments form `<name..>` so the captured name
      # matches the `{name}` placeholder canonicalize_rocket_path emits.
      path_part.scan(/<(\w+)(?:\.\.)?>/) do |match|
        name = match[1]
        params << Param.new(name, "", "path") unless params.any? { |p| p.name == name && p.param_type == "path" }
      end

      if query_part
        query_part.scan(/<(\w+)>/) do |match|
          name = match[1]
          params << Param.new(name, "", "query") unless params.any? { |p| p.name == name && p.param_type == "query" }
        end
      end

      if data_param && !data_param.empty?
        params << Param.new(data_param, "", "body")
      end

      params
    end

    # Cookies and headers come from the function signature + body.
    # The `CookieJar` signature gate from the legacy analyzer is
    # preserved — `cookies.get(...)` only counts when the function
    # actually takes a `CookieJar`.
    private def extract_function_extras(function : LibTreeSitter::TSNode,
                                        source : String,
                                        endpoint : Endpoint)
      has_cookie_jar = false
      params_node = Noir::TreeSitter.field(function, "parameters")
      if params_node
        Noir::TreeSitter.each_named_child(params_node) do |param|
          has_cookie_jar = true if Noir::TreeSitter.node_text(param, source).includes?("CookieJar")
        end
      end

      body = Noir::TreeSitter.field(function, "body")
      return unless body

      walk(body) do |call|
        next unless Noir::TreeSitter.node_type(call) == "call_expression"
        fn_text = call_function_text(call, source)
        next if fn_text.nil?

        if has_cookie_jar && (fn_text.ends_with?(".get") || fn_text.ends_with?(".get_private"))
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "cookie" }
            endpoint.push_param(Param.new(name, "", "cookie"))
          end
        elsif fn_text.ends_with?(".headers().get")
          name = first_string_literal_text(Noir::TreeSitter.field(call, "arguments"), source)
          if name && !endpoint.params.any? { |p| p.name == name && p.param_type == "header" }
            endpoint.push_param(Param.new(name, "", "header"))
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
