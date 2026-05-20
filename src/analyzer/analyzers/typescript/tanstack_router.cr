require "../../engines/javascript_engine"
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

      parallel_file_scan([".ts", ".tsx"]) do |path|
        analyze_tanstack_file(path, result)
      end

      result
    end

    private def analyze_tanstack_file(path : String, result : Array(Endpoint))
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Extract routes from createFileRoute
        analyze_file_routes(content, path, result)

        # Extract code-based route trees from createRoute
        analyze_create_routes(content, path, result)

        # Extract routes from createLazyFileRoute
        analyze_lazy_file_routes(content, path, result)
      end
    rescue e : Exception
      logger.debug "Error analyzing TanStack Router file #{path}: #{e.message}"
    end

    private def analyze_file_routes(content : String, path : String, result : Array(Endpoint))
      # Pattern for createFileRoute('/path')
      # Example: export const Route = createFileRoute('/posts/$postId')()
      file_route_pattern = /createFileRoute\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/

      content.scan(file_route_pattern) do |match|
        if match.size > 0
          route_path = match[1]
          # Convert TanStack Router path params ($param) to standard format (:param)
          normalized_path = normalize_path(route_path)

          endpoint = create_endpoint(normalized_path, "GET", path)
          extract_path_parameters(normalized_path, endpoint)
          extract_search_params(content, endpoint)
          result << endpoint
        end
      end
    end

    private def analyze_lazy_file_routes(content : String, path : String, result : Array(Endpoint))
      # Pattern for createLazyFileRoute('/path')
      # Example: export const Route = createLazyFileRoute('/posts/$postId')()
      lazy_file_route_pattern = /createLazyFileRoute\s*\(\s*['"`]([^'"`]+)['"`]\s*\)/

      content.scan(lazy_file_route_pattern) do |match|
        if match.size > 0
          route_path = match[1]
          normalized_path = normalize_path(route_path)

          endpoint = create_endpoint(normalized_path, "GET", path)
          extract_path_parameters(normalized_path, endpoint)
          extract_search_params(content, endpoint)
          result << endpoint
        end
      end
    end

    private def analyze_create_routes(content : String, path : String, result : Array(Endpoint))
      routes = extract_code_routes(content)
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
          result << endpoint
        end
      end

      # Also handle createRootRoute with path
      root_route_pattern = /createRootRoute(?:WithContext(?:\s*<[^>]+>)?\s*\(\s*\))?\s*\(\s*\{[^}]*path\s*:\s*['"`]([^'"`]+)['"`][^}]*\}/

      content.scan(root_route_pattern) do |match|
        if match.size > 0
          route_path = match[1]
          normalized_path = normalize_path(route_path)

          endpoint = create_endpoint(normalized_path, "GET", path, match.begin(0) || 0, content)
          extract_path_parameters(normalized_path, endpoint)
          result << endpoint
        end
      end
    end

    private def extract_code_routes(content : String) : Array(CodeRoute)
      routes = [] of CodeRoute
      assignment_pattern = /\b(?:export\s+)?(?:const|let|var)\s+(\w+)\s*=\s*createRoute\s*\(/

      content.scan(assignment_pattern) do |match|
        start_pos = match.begin(0)
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

    private def extract_string_property(block : String, property : String) : String?
      escaped_property = Regex.escape(property)
      match = block.match(/(?:^|[,{]\s*)#{escaped_property}\s*:\s*['"`]([^'"`]+)['"`]/m)
      match.try(&.[1])
    end

    private def extract_parent_route(block : String) : String?
      match = block.match(/getParentRoute\s*:\s*\(\s*\)\s*=>\s*([A-Za-z_$][\w$]*)/)
      match.try(&.[1])
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
      stripped.starts_with?("_") && !stripped.empty?
    end

    private def normalize_path(path : String) : String
      # TanStack Router uses $param for path parameters
      # Convert to standard :param format
      path.gsub(/\$(\w+)/, ":\\1")
    end

    private def create_endpoint(url : String, method : String, file_path : String, start_pos : Int32 = 0, content : String = "") : Endpoint
      endpoint = Endpoint.new(url, method)
      line = content.empty? ? 1 : content.to_slice[0, start_pos].count('\n'.ord.to_u8) + 1
      endpoint.details = Details.new(PathInfo.new(file_path, line))
      endpoint
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

      # Look for useSearch hook usage
      # Example: const { page, filter } = Route.useSearch()
      use_search_pattern = /(?:const|let|var)\s*\{([^}]+)\}\s*=\s*(?:Route\.)?useSearch\s*\(/
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
    end

    private def extract_search_params_from_route_block(route_block : String, endpoint : Endpoint)
      # Extract search params from the route definition block
      extract_search_params(route_block, endpoint)
    end
  end
end
