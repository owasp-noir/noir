require "../../engines/javascript_engine"
require "../../../miniparsers/js_callee_extractor"
require "../../../miniparsers/js_route_extractor"

module Analyzer::Typescript
  class TanstackRouter < Analyzer::Javascript::JavascriptEngine
    private struct CodeRoute
      getter name : String
      getter path : String
      getter parent : String?
      getter block : String
      getter start_pos : Int32

      def initialize(@name : String, @path : String, @parent : String?, @block : String, @start_pos : Int32)
      end
    end

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

    private def tanstack_route_candidate?(content : String) : Bool
      ROUTE_CONSTRUCTOR_HINTS.any? { |hint| content.includes?(hint) }
    end

    TEST_FIXTURE_PATH_MARKERS = [
      "/test/",
      "/tests/",
      "/__tests__/",
      "/e2e/",
      "/snapshots/",
      "/test-files/",
    ]

    private def tanstack_test_fixture_path?(path : String) : Bool
      TEST_FIXTURE_PATH_MARKERS.any? { |marker| path.includes?(marker) } ||
        path.includes?(".test.") ||
        path.includes?(".spec.")
    end

    private def analyze_file_routes(content : String, path : String, result : Array(Endpoint), literal_mask : Array(Bool))
      # Pattern for createFileRoute('/path')
      # Example: export const Route = createFileRoute('/posts/$postId')()
      # A trailing comma is tolerated so a formatter-wrapped multi-line call
      # (`createFileRoute(\n  '/path',\n)`) is still matched.
      file_route_pattern = /createFileRoute\s*\(\s*['"`]([^'"`]+)['"`]\s*,?\s*\)/

      content.scan(file_route_pattern) do |match|
        next if literal_position?(literal_mask, match.begin(0))

        if match.size > 0
          route_path = match[1]
          next if pathless_only_route?(route_path)

          # Convert TanStack Router path params ($param) to standard format (:param)
          normalized_path = normalize_path(route_path)

          endpoint = create_endpoint(normalized_path, "GET", path, match.begin(0) || 0, content)
          extract_path_parameters(normalized_path, endpoint)
          extract_search_params(content, endpoint)
          attach_file_route_callees(content, path, match.begin(0) || 0, endpoint) if callees_needed?
          result << endpoint
        end
      end
    end

    private def analyze_lazy_file_routes(content : String, path : String, result : Array(Endpoint), literal_mask : Array(Bool))
      # Pattern for createLazyFileRoute('/path')
      # Example: export const Route = createLazyFileRoute('/posts/$postId')()
      lazy_file_route_pattern = /createLazyFileRoute\s*\(\s*['"`]([^'"`]+)['"`]\s*,?\s*\)/

      content.scan(lazy_file_route_pattern) do |match|
        next if literal_position?(literal_mask, match.begin(0))

        if match.size > 0
          route_path = match[1]
          next if pathless_only_route?(route_path)

          normalized_path = normalize_path(route_path)

          endpoint = create_endpoint(normalized_path, "GET", path, match.begin(0) || 0, content)
          extract_path_parameters(normalized_path, endpoint)
          extract_search_params(content, endpoint)
          attach_file_route_callees(content, path, match.begin(0) || 0, endpoint) if callees_needed?
          result << endpoint
        end
      end
    end

    private def analyze_create_routes(content : String, path : String, result : Array(Endpoint), literal_mask : Array(Bool))
      routes = extract_code_routes(content, literal_mask)
      unless routes.empty?
        route_map = Hash(String, CodeRoute).new
        routes.each { |route| route_map[route.name] = route }

        routes.each do |route|
          next if pathless_segment?(route.path)

          resolved_path = resolve_code_route_path(route, route_map)
          next if resolved_path.empty?

          endpoint = create_endpoint(resolved_path, "GET", path, route.start_pos, content)
          extract_path_parameters(resolved_path, endpoint)
          extract_search_params_from_route_block(route.block, endpoint)
          attach_route_block_callees(route.block, path, line_for_pos(content, route.start_pos), endpoint) if callees_needed?
          result << endpoint
        end
      end

      # Also handle createRootRoute with path
      root_route_pattern = /createRootRoute(?:WithContext(?:\s*<[^>]+>)?\s*\(\s*\))?\s*\(\s*\{[^}]*path\s*:\s*['"`]([^'"`]+)['"`][^}]*\}/

      content.scan(root_route_pattern) do |match|
        next if literal_position?(literal_mask, match.begin(0))

        if match.size > 0
          route_path = match[1]
          normalized_path = normalize_path(route_path)

          endpoint = create_endpoint(normalized_path, "GET", path, match.begin(0) || 0, content)
          extract_path_parameters(normalized_path, endpoint)
          attach_route_block_callees(match[0], path, line_for_pos(content, match.begin(0) || 0), endpoint) if callees_needed?
          result << endpoint
        end
      end
    end

    private def extract_code_routes(content : String, literal_mask : Array(Bool)) : Array(CodeRoute)
      routes = [] of CodeRoute
      assignment_pattern = /\b(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*createRoute\s*\(/

      content.scan(assignment_pattern) do |match|
        start_pos = match.begin(0)
        next if literal_position?(literal_mask, start_pos)

        open_paren = match.end(0).try { |idx| content.rindex('(', idx - 1) }
        next unless start_pos && open_paren

        close_paren = Noir::JSRouteExtractor.find_matching_paren(content, open_paren)
        next unless close_paren

        block = content[(open_paren + 1)...close_paren]
        route_path = extract_string_property(block, "path")
        next unless route_path

        parent = extract_parent_route(block)
        routes << CodeRoute.new(match[1], route_path, parent, block, start_pos)
      end

      routes
    end

    private def string_literal_mask(content : String) : Array(Bool)
      mask = Array(Bool).new(content.bytesize, false)
      i = 0

      while i < content.bytesize
        byte = content.byte_at(i)
        if byte == '\''.ord || byte == '"'.ord || byte == '`'.ord
          quote = byte
          mask[i] = true
          i += 1

          while i < content.bytesize
            current = content.byte_at(i)
            mask[i] = true

            if current == '\\'.ord && i + 1 < content.bytesize
              i += 1
              mask[i] = true
            elsif current == quote
              i += 1
              break
            end

            i += 1
          end
        else
          i += 1
        end
      end

      mask
    end

    private def literal_position?(literal_mask : Array(Bool), pos : Int32?) : Bool
      return false unless pos
      pos < literal_mask.size && literal_mask[pos]
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
      normalized = path.gsub_repeatedly("//", "/")
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

    private def create_endpoint(url : String, method : String, file_path : String, start_pos : Int32 = 0, content : String = "") : Endpoint
      endpoint = Endpoint.new(url, method)
      line = content.empty? ? 1 : content.to_slice[0, start_pos].count('\n'.ord.to_u8) + 1
      endpoint.details = Details.new(PathInfo.new(file_path, line))
      endpoint
    end

    private def attach_file_route_callees(content : String, path : String, start_pos : Int32, endpoint : Endpoint)
      call_open = content.index('(', start_pos)
      return unless call_open
      call_close = Noir::JSRouteExtractor.find_matching_paren(content, call_open)
      return unless call_close

      second_call_open = skip_whitespace(content, call_close + 1)
      return unless content[second_call_open]? == '('

      config_open = skip_whitespace(content, second_call_open + 1)
      return unless content[config_open]? == '{'

      second_call_close = Noir::JSRouteExtractor.find_matching_paren(content, second_call_open)
      return unless second_call_close

      config_close = Noir::JSRouteExtractor.find_matching_brace(content, config_open)
      return unless config_close
      return if config_close > second_call_close

      block = content[(config_open + 1)...config_close]
      attach_route_block_callees(block, path, line_for_pos(content, config_open), endpoint)
    end

    private def skip_whitespace(content : String, pos : Int32) : Int32
      i = pos
      while i < content.size && content[i].whitespace?
        i += 1
      end
      i
    end

    private def attach_route_block_callees(block : String, path : String, start_line : Int32, endpoint : Endpoint)
      attach_identifier_slot_callees(block, path, start_line, endpoint)
      attach_function_slot_callees(block, path, start_line, endpoint)
    end

    private def attach_identifier_slot_callees(block : String, path : String, start_line : Int32, endpoint : Endpoint)
      block.scan(/\b(component|loader|beforeLoad|pendingComponent|errorComponent)\s*:\s*([A-Za-z_$][\w$]*)/) do |match|
        line = start_line + block[0, match.begin(2) || 0].count('\n')
        endpoint.push_callee(Callee.new(match[2], path: path, line: line))
      end
    end

    private def attach_function_slot_callees(block : String, path : String, start_line : Int32, endpoint : Endpoint)
      block.scan(/\b(loader|beforeLoad)\s*:\s*(?:async\s*)?(?:\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>/) do |match|
        body_start = match.end(0) || 0
        body = block[body_start..]?.try(&.strip) || ""
        line = start_line + block[0, body_start].count('\n')
        if body.starts_with?("{")
          if close = Noir::JSRouteExtractor.find_matching_brace(body, 0)
            body = body[1...close]
          end
        end
        Noir::JSCalleeExtractor.callees_for_function_body(body, path, line, language: javascript_source_language(path)).each do |name, callee_path, callee_line|
          endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
        end
      end
    end

    private def line_for_pos(content : String, pos : Int32) : Int32
      content[0, pos].count('\n') + 1
    end

    private def extract_path_parameters(url : String, endpoint : Endpoint)
      # Extract path parameters from URL patterns like :id or $id
      url.scan(/:(\w+)/) do |match|
        if match.size > 0
          param_name = match[1]
          unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "path" }
            endpoint.push_param(Param.new(param_name, "", "path"))
          end
        end
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
        if match.size > 0
          schema_content = match[1]
          # Extract param names from schema
          schema_content.scan(/(\w+)\s*:/) do |param_match|
            if param_match.size > 0
              param_name = param_match[1]
              unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
                endpoint.push_param(Param.new(param_name, "", "query"))
              end
            end
          end
        end
      end

      # Also look for search object definitions
      # Example: search: { page: 1, filter: '' }
      search_object_pattern = /search\s*:\s*\{([^}]+)\}/
      content.scan(search_object_pattern) do |match|
        if match.size > 0
          search_content = match[1]
          search_content.scan(/(\w+)\s*:/) do |param_match|
            if param_match.size > 0
              param_name = param_match[1]
              unless endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
                endpoint.push_param(Param.new(param_name, "", "query"))
              end
            end
          end
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
        if match.size > 0
          params_str = match[1]
          params_str.split(",").each do |param|
            param_name = param.strip.split(":").first.strip.split("=").first.strip
            unless param_name.empty? || endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }
              endpoint.push_param(Param.new(param_name, "", "query"))
            end
          end
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
      i = start

      while i < text.size
        char = text[i]

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
      return if endpoint.params.any? { |p| p.name == param_name && p.param_type == "query" }

      endpoint.push_param(Param.new(param_name, "", "query"))
    end
  end
end
