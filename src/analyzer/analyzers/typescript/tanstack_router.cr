require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Typescript
  class TanstackRouter < Analyzer::Javascript::JavascriptEngine
    analyzer_for "ts_tanstack_router"

    # `start_pos` is a CHAR index (used for char-based navigation);
    # `byte_start_pos` is the same position as a BYTE offset (used for
    # the byte-indexed literal mask and newline counting).
    private record CodeRoute, name : String, path : String, parent : String?, block : String, start_pos : Int32, byte_start_pos : Int32

    def analyze
      result = [] of Endpoint
      mutex = Mutex.new

      parallel_file_scan([".ts", ".tsx"]) do |path|
        # Collect into a per-file buffer, then merge under the mutex —
        # `parallel_file_scan` can run concurrently, so appending straight
        # to the shared `result` risks a lost/duplicated endpoint.
        file_endpoints = [] of Endpoint
        analyze_tanstack_file(path, file_endpoints)
        unless file_endpoints.empty?
          mutex.synchronize { result.concat(file_endpoints) }
        end
      end

      result
    end

    private def analyze_tanstack_file(path : String, result : Array(Endpoint))
      return if tanstack_test_fixture_path?(path)

      raw = read_file_content(path)
      return unless tanstack_route_candidate?(raw)
      return if storybook_story?(path, raw)
      # TanStack Router route files are React/Vue components — don't let the
      # client-side-framework markers skip them (they all import `react`).
      return if Noir::JSRouteExtractor.test_stub_only?(path, raw, include_client_frameworks: false)

      # Comments can hold stale routes; drop them so a commented-out
      # `createFileRoute('/old')` doesn't get reported.
      content = Noir::JSRouteExtractor.strip_js_comments(raw)
      return unless tanstack_route_candidate?(content)

      literal_mask = string_literal_mask(content)

      # Extract routes from createFileRoute
      analyze_file_routes(content, path, result, literal_mask)

      # Extract code-based route trees from createRoute
      analyze_create_routes(content, path, result, literal_mask)

      # Extract routes from createLazyFileRoute
      analyze_lazy_file_routes(content, path, result, literal_mask)
    rescue e : Exception
      logger.debug "Error analyzing TanStack Router file #{path}: #{e.message}"
    end

    ROUTE_CONSTRUCTOR_HINTS = [
      "createFileRoute",
      "createLazyFileRoute",
      "createRoute",
      "createRootRoute",
      "createRootRouteWithContext",
    ]
    # One precompiled `Regex.union` (PCRE2 JIT) scan replaces five sequential
    # `String#includes?` calls — this gate runs on every scanned .ts/.tsx
    # file's raw content, twice (once pre- and once post-comment-strip).
    ROUTE_CONSTRUCTOR_RE = Regex.union(ROUTE_CONSTRUCTOR_HINTS)
    FILE_ROUTE_CALL_RE   = /\bcreate(?:Lazy)?FileRoute\s*\(/

    private def tanstack_route_candidate?(content : String) : Bool
      content.matches?(ROUTE_CONSTRUCTOR_RE)
    end

    TEST_FIXTURE_PATH_MARKERS = [
      "/test/",
      "/tests/",
      "/__tests__/",
      "/e2e/",
      "/snapshots/",
      "/test-files/",
    ]

    # Scan-base-relative, never absolute: a `test/` directory ABOVE the
    # scan base is not this project's test tree.
    private def tanstack_test_fixture_path?(path : String) : Bool
      relative = base_relative_path(path)
      TEST_FIXTURE_PATH_MARKERS.any? { |marker| relative.includes?(marker) } ||
        relative.includes?(".test.") ||
        relative.includes?(".spec.")
    end

    # A Storybook story (`Admin.stories.tsx`) builds a throwaway router with
    # `createRoute`/`createRootRoute` to render a page. File-route modules
    # (`createFileRoute`) are never built that way, and a flat route can
    # legitimately be named `user.$userId.stories.tsx`.
    private def storybook_story?(path : String, raw : String) : Bool
      base_relative_path(path).includes?(".stories.") && !raw.matches?(FILE_ROUTE_CALL_RE)
    end

    private def analyze_file_routes(content : String, path : String, result : Array(Endpoint), literal_mask : Array(Bool))
      # Pattern for createFileRoute('/path')
      # Example: export const Route = createFileRoute('/posts/$postId')()
      # A trailing comma is tolerated so a formatter-wrapped multi-line call
      # (`createFileRoute(\n  '/path',\n)`) is still matched.
      file_route_pattern = /createFileRoute\s*\(\s*['"`]([^'"`]+)['"`]\s*,?\s*\)/

      content.scan(file_route_pattern) do |match|
        # The literal mask is BYTE-indexed — probe it with the match's byte
        # offset. The previous char-index probe drifted on any file with a
        # multi-byte char before the route, silently degrading the
        # in-literal filtering.
        next if literal_position?(literal_mask, match.byte_begin(0))

        route_path = match[1]
        next if pathless_only_route?(route_path)

        # Convert TanStack Router path params ($param) to standard format (:param)
        normalized_path = normalize_path(route_path)

        endpoint = create_endpoint(normalized_path, "GET", path, match.byte_begin(0), content)
        extract_path_parameters(normalized_path, endpoint)
        extract_search_params(content, endpoint)
        attach_file_route_callees(content, path, match.begin(0) || 0, endpoint) if callees_needed?
        result << endpoint
      end
    end

    private def analyze_lazy_file_routes(content : String, path : String, result : Array(Endpoint), literal_mask : Array(Bool))
      # Pattern for createLazyFileRoute('/path')
      # Example: export const Route = createLazyFileRoute('/posts/$postId')()
      lazy_file_route_pattern = /createLazyFileRoute\s*\(\s*['"`]([^'"`]+)['"`]\s*,?\s*\)/

      content.scan(lazy_file_route_pattern) do |match|
        next if literal_position?(literal_mask, match.byte_begin(0))

        route_path = match[1]
        next if pathless_only_route?(route_path)

        normalized_path = normalize_path(route_path)

        endpoint = create_endpoint(normalized_path, "GET", path, match.byte_begin(0), content)
        extract_path_parameters(normalized_path, endpoint)
        extract_search_params(content, endpoint)
        attach_file_route_callees(content, path, match.begin(0) || 0, endpoint) if callees_needed?
        result << endpoint
      end
    end

    private def analyze_create_routes(content : String, path : String, result : Array(Endpoint), literal_mask : Array(Bool))
      routes = extract_code_routes(content, path)
      unless routes.empty?
        route_map = Hash(String, CodeRoute).new
        routes.each { |route| route_map[route.name] = route }

        routes.each do |route|
          next if pathless_segment?(route.path)

          resolved_path = resolve_code_route_path(route, route_map)
          next if resolved_path.empty?

          endpoint = create_endpoint(resolved_path, "GET", path, route.byte_start_pos, content)
          extract_path_parameters(resolved_path, endpoint)
          extract_search_params_from_route_block(route.block, endpoint)
          attach_route_block_callees(route.block, path, line_for_byte_pos(content, route.byte_start_pos), endpoint) if callees_needed?
          result << endpoint
        end
      end

      # Also handle createRootRoute with path
      root_route_pattern = /createRootRoute(?:WithContext(?:\s*<[^>]+>)?\s*\(\s*\))?\s*\(\s*\{[^}]*path\s*:\s*['"`]([^'"`]+)['"`][^}]*\}/

      content.scan(root_route_pattern) do |match|
        next if literal_position?(literal_mask, match.byte_begin(0))

        route_path = match[1]
        normalized_path = normalize_path(route_path)

        endpoint = create_endpoint(normalized_path, "GET", path, match.byte_begin(0), content)
        extract_path_parameters(normalized_path, endpoint)
        attach_route_block_callees(match[0], path, line_for_byte_pos(content, match.byte_begin(0)), endpoint) if callees_needed?
        result << endpoint
      end
    end

    # `const name = createRoute({...})` declarations; the block is the
    # call's argument text.
    private def extract_code_routes(content : String, path : String) : Array(CodeRoute)
      routes = [] of CodeRoute
      Noir::TreeSitter.parse_js_family(content, path) do |root|
        Noir::TreeSitter.walk(root) do |node|
          next unless Noir::TreeSitter.node_type(node) == "variable_declarator"
          name = Noir::TreeSitter.field(node, "name")
          call = Noir::TreeSitter.field(node, "value").try { |value| Noir::TreeSitter.unwrap_expression(value) }
          next unless name && call && Noir::TreeSitter.node_type(name) == "identifier" && Noir::TreeSitter.node_type(call) == "call_expression"
          function = Noir::TreeSitter.field(call, "function")
          next unless function && Noir::TreeSitter.node_text(function, content) == "createRoute"
          args = Noir::TreeSitter.field(call, "arguments") || next

          block = Noir::TreeSitter.node_text(args, content)
          block = block[1...-1] if block.starts_with?('(') && block.ends_with?(')')
          route_path = extract_string_property(block, "path") || next

          # The statement (`export const ...`) is where the route starts.
          statement = Noir::TreeSitter.parent(node)
          statement = Noir::TreeSitter.parent(statement) if statement && Noir::TreeSitter.parent(statement).try { |outer| Noir::TreeSitter.node_type(outer) == "export_statement" }
          byte_start = LibTreeSitter.ts_node_start_byte(statement || node).to_i
          routes << CodeRoute.new(Noir::TreeSitter.node_text(name, content), route_path, extract_parent_route(block), block, content.byte_slice(0, byte_start).size, byte_start)
        end
      end
      routes
    end

    private def extract_string_property(block : String, property : String) : String?
      property_re = cached_regex("tanstack:string_prop:#{property}") do
        /(?:^|[,{]\s*)#{Regex.escape(property)}\s*:\s*['"`]([^'"`]+)['"`]/m
      end
      match = block.match(property_re)
      match.try(&.[1])
    end

    private def extract_parent_route(block : String) : String?
      # Tolerate parens around the identifier, e.g. `() => (rootRoute)`,
      # and arrow-body bracing like `() => { return rootRoute }`, which
      # both show up in real-world TanStack apps when teams add an
      # explicit `return` for clarity.
      arrow_match = block.match(/getParentRoute\s*:\s*\(\s*\)\s*=>\s*\(?\s*([A-Za-z_$][\w$]*)\s*\)?/)
      return arrow_match[1] if arrow_match

      body_match = block.match(/getParentRoute\s*\(\s*\)\s*\{\s*return\s+([A-Za-z_$][\w$]*)/)
      body_match.try(&.[1])
    end

    private def resolve_code_route_path(route : CodeRoute, route_map : Hash(String, CodeRoute), resolving = Set(String).new) : String
      return "/" if resolving.includes?(route.name)

      resolving.add(route.name)

      parent_path = ""
      if parent = route.parent
        if parent_route = route_map[parent]?
          parent_path = resolve_code_route_path(parent_route, route_map, resolving)
        end
      end

      resolving.delete(route.name)
      combine_route_paths(parent_path, route.path)
    end

    private def combine_route_paths(parent : String, child : String) : String
      normalized_child = normalize_path(child)

      return normalize_url_path(parent) if normalized_child == "/" || pathless_segment?(child)
      return normalize_url_path(normalized_child) if parent.empty? || parent == "/"

      parent = parent.chomp("/")
      child_part = normalized_child.starts_with?("/") ? normalized_child[1..-1] : normalized_child
      normalize_url_path("#{parent}/#{child_part}")
    end

    private def normalize_url_path(path : String) : String
      normalized = path.squeeze('/')
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized = normalized.chomp("/") unless normalized == "/"
      normalized
    end

    private def pathless_segment?(path : String) : Bool
      stripped = path.strip.lstrip('/').rstrip('/')
      return false if stripped.empty?
      # Organizational-only segments that never contribute to the URL:
      # `_layout` pathless layouts (leading underscore) and `(group)`
      # route groups (`app/routes/(marketing)/about` serves `/about`).
      stripped.starts_with?("_") ||
        (stripped.starts_with?("(") && stripped.ends_with?(")"))
    end

    private def pathless_only_route?(path : String) : Bool
      segments = path.split('/').reject(&.empty?)
      !segments.empty? && segments.all? { |segment| pathless_segment?(segment) }
    end

    private def normalize_path(path : String) : String
      # TanStack Router uses $param for path parameters
      # Convert to standard :param format
      normalized = path.gsub(/\$(\w+)/, ":\\1")
      remove_pathless_segments(normalized)
    end

    private def remove_pathless_segments(path : String) : String
      absolute = path.starts_with?("/")
      kept = path.split('/').reject(&.empty?).reject { |segment| pathless_segment?(segment) }
      return "/" if kept.empty?

      normalized = kept.join("/")
      absolute ? "/#{normalized}" : normalized
    end

    # `byte_start_pos` must be a BYTE offset (`Regex::MatchData#byte_begin`
    # or `CodeRoute#byte_start_pos`) — the previous version sliced the byte
    # buffer with a char index, under-counting lines on any file with a
    # multi-byte char before the route.
    private def create_endpoint(url : String, method : String, file_path : String, byte_start_pos : Int32 = 0, content : String = "") : Endpoint
      endpoint = Endpoint.new(url, method)
      line = content.empty? ? 1 : line_for_byte_pos(content, byte_start_pos)
      endpoint.details = Details.new(PathInfo.new(file_path, line))
      endpoint
    end

    # `createFileRoute("/x")({...})` starting at `start_pos`: the config
    # object is the argument of the call that call returns.
    private def attach_file_route_callees(content : String, path : String, start_pos : Int32, endpoint : Endpoint)
      line = line_number_for_index(content, start_pos)
      references = [] of Callee
      bodies = [] of Callee
      Noir::TreeSitter.parse_js_family(content, path) do |root|
        Noir::TreeSitter.walk(root) do |node|
          next unless references.empty? && bodies.empty? && Noir::TreeSitter.node_type(node) == "call_expression"
          factory = Noir::TreeSitter.field(node, "function").try { |f| Noir::TreeSitter.unwrap_expression(f) }
          next unless factory && Noir::TreeSitter.node_type(factory) == "call_expression"
          name = Noir::TreeSitter.field(factory, "function")
          next unless name && Noir::TreeSitter.node_start_row(name) + 1 == line
          next unless FILE_ROUTE_FACTORIES.includes?(Noir::TreeSitter.node_text(name, content))
          args = Noir::TreeSitter.field(node, "arguments") || next
          config = Noir::TreeSitter.first_named_arg(args).try { |arg| Noir::TreeSitter.unwrap_expression(arg) }
          collect_route_slots(config, content, path, 1, references, bodies) if config
        end
      end
      (references + bodies).each { |callee| endpoint.push_callee(callee) }
    end

    ROUTE_REFERENCE_SLOTS = Set{"component", "loader", "beforeLoad", "pendingComponent", "errorComponent"}
    ROUTE_FUNCTION_SLOTS  = Set{"loader", "beforeLoad"}

    FILE_ROUTE_FACTORIES = Set{"createFileRoute", "createLazyFileRoute"}

    # The first object in `block`, a call such as `createRoute({...})`, is the
    # route's config; `start_line` is the line the block starts on.
    private def attach_route_block_callees(block : String, path : String, start_line : Int32, endpoint : Endpoint)
      references = [] of Callee
      bodies = [] of Callee
      Noir::TreeSitter.parse_js_family(block, path) do |root|
        first_object(root).try { |object| collect_route_slots(object, block, path, start_line, references, bodies) }
      end
      (references + bodies).each { |callee| endpoint.push_callee(callee) }
    end

    # A slot naming a function (`component: Page`) is a callee, and the body
    # of an inline `loader` / `beforeLoad` is walked for its own. `start_line`
    # is the line of `source`'s first row.
    private def collect_route_slots(object : LibTreeSitter::TSNode, source : String, path : String, start_line : Int32,
                                    references : Array(Callee), bodies : Array(Callee))
      return unless Noir::TreeSitter.node_type(object) == "object"
      Noir::TreeSitter.each_named_child(object) do |member|
        next unless Noir::TreeSitter.node_type(member) == "pair"
        key = Noir::TreeSitter.field(member, "key").try { |node| Noir::TreeSitter.node_text(node, source).strip("'\"") }
        value = Noir::TreeSitter.field(member, "value").try { |node| Noir::TreeSitter.unwrap_expression(node) }
        next unless key && value && ROUTE_REFERENCE_SLOTS.includes?(key)

        case Noir::TreeSitter.node_type(value)
        when "identifier"
          references << Callee.new(Noir::TreeSitter.node_text(value, source), path: path, line: start_line + Noir::TreeSitter.node_start_row(value))
        when "arrow_function", "function_expression"
          next unless ROUTE_FUNCTION_SLOTS.includes?(key)
          Noir::JSCalleeExtractor.callees_for_handler_node(value, source, path).each do |name, callee_path, line|
            bodies << Callee.new(name, path: callee_path, line: start_line + line - 1)
          end
        end
      end
    end

    private def first_object(root : LibTreeSitter::TSNode) : LibTreeSitter::TSNode?
      found = nil.as(LibTreeSitter::TSNode?)
      Noir::TreeSitter.walk(root) do |node|
        found = node if found.nil? && Noir::TreeSitter.node_type(node) == "object"
      end
      found
    end

    private def line_for_byte_pos(content : String, byte_pos : Int32) : Int32
      content.to_slice[0, byte_pos].count('\n'.ord.to_u8) + 1
    end

    private def extract_path_parameters(url : String, endpoint : Endpoint)
      # Extract path parameters from URL patterns like :id or $id
      url.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    private def extract_search_params(content : String, endpoint : Endpoint)
      # TanStack Router uses validateSearch or search for query params
      # Example: validateSearch: (search) => ({ page: search.page || 1 })
      # Example: search: { page: 1, filter: '' }

      # Look for search schema definitions using zod or similar
      # Example: validateSearch: z.object({ page: z.number(), filter: z.string() })
      search_schema_pattern = /validateSearch\s*:\s*z\.object\s*\(\s*\{([^}]+)\}/
      content.scan(search_schema_pattern) do |match|
        schema_content = match[1]
        # Extract param names from schema
        schema_content.scan(/(\w+)\s*:/) do |param_match|
          param_name = param_match[1]
          endpoint.push_param(Param.new(param_name, "", "query"))
        end
      end

      # Also look for search object definitions
      # Example: search: { page: 1, filter: '' }
      search_object_pattern = /search\s*:\s*\{([^}]+)\}/
      content.scan(search_object_pattern) do |match|
        search_content = match[1]
        search_content.scan(/(\w+)\s*:/) do |param_match|
          param_name = param_match[1]
          endpoint.push_param(Param.new(param_name, "", "query"))
        end
      end

      extract_validate_search_function_params(content, endpoint)

      # Look for useSearch hook usage. Three call shapes show up
      # across TanStack v1 apps:
      #   - Route.useSearch()                       (file-route scope)
      #   - useSearch({ from: '/posts' })           (component-level)
      #   - getRouteApi('/posts').useSearch()       (extracted API)
      # All three should map search-destructured names back to query
      # params on the corresponding route.
      use_search_pattern = /(?:const|let|var)\s*\{([^}]+)\}\s*=\s*(?:Route\.|[\w$]+\.)?useSearch\s*\(/
      content.scan(use_search_pattern) do |match|
        params_str = match[1]
        params_str.split(",").each do |param|
          param_name = param.strip.split(":").first.strip.split("=").first.strip
          endpoint.push_param(Param.new(param_name, "", "query")) unless param_name.empty?
        end
      end

      # `getRouteApi('/path').useSearch()` produces a `search` value
      # that's typically used field-by-field afterwards. Treat any
      # destructured names from the search return value the same as
      # the Route.useSearch case above. Pattern handled by the unified
      # regex already.
    end

    private def extract_search_params_from_route_block(route_block : String, endpoint : Endpoint)
      # Extract search params from the route definition block
      extract_search_params(route_block, endpoint)
    end

    private def extract_validate_search_function_params(content : String, endpoint : Endpoint)
      content.scan(/\bvalidateSearch\s*:/) do |match|
        value_start = match.end(0) || 0
        value_end = skip_top_level_to_comma(content, value_start)
        value = content[value_start...value_end]
        search_name = validate_search_argument_name(value)
        next unless search_name

        value.scan(cached_regex("tanstack:search_dot:#{search_name}") { /\b#{Regex.escape(search_name)}\s*\.\s*([A-Za-z_$][\w$]*)/ }) do |param_match|
          push_unique_query_param(endpoint, param_match[1])
        end

        value.scan(cached_regex("tanstack:search_destructure:#{search_name}") { /\b(?:const|let|var)\s*\{([^}]+)\}\s*=\s*#{Regex.escape(search_name)}\b/ }) do |destructure_match|
          destructure_match[1].split(",").each do |param|
            param_name = param.strip.split(":").first.strip.split("=").first.strip
            push_unique_query_param(endpoint, param_name)
          end
        end
      end
    end

    private def validate_search_argument_name(value : String) : String?
      if match = value.match(/\A\s*(?:async\s*)?\(\s*([A-Za-z_$][\w$]*)\b/)
        match[1]
      elsif match = value.match(/\A\s*(?:async\s*)?([A-Za-z_$][\w$]*)\s*=>/)
        match[1]
      elsif match = value.match(/\A\s*(?:async\s*)?function[^(]*\(\s*([A-Za-z_$][\w$]*)\b/)
        match[1]
      end
    end

    private def skip_top_level_to_comma(text : String, start : Int32) : Int32
      depth = 0
      quote : Char? = nil
      escaped = false
      # `text[i]` walks a non-ASCII String from byte 0 on every call (Crystal
      # has no char-index cache), turning this scan O(n) per char -> O(n^2)
      # over a `validateSearch:` value. Materializing `chars` once makes
      # every access O(1).
      chars = text.chars
      n = chars.size
      i = start

      while i < n
        char = chars[i]

        if quote
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
          i += 1
          next
        end

        case char
        when '\'', '"', '`'
          quote = char
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          return i if depth == 0
        end

        i += 1
      end

      i
    end

    private def push_unique_query_param(endpoint : Endpoint, param_name : String)
      return if param_name.empty?

      endpoint.push_param(Param.new(param_name, "", "query"))
    end
  end
end
