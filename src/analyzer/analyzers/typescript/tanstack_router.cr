require "../../../models/analyzer"

module Analyzer::Typescript
  class TanstackRouter < Analyzer
    def analyze
      channel = Channel(String).new
      result = [] of Endpoint

      begin
        populate_channel_with_files(channel)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless [".ts", ".tsx"].any? { |ext| path.ends_with?(ext) }

          if File.exists?(path)
            analyze_tanstack_file(path, result)
          end
        end
      rescue e : Exception
        logger.debug "Channel or wait group error: #{e.message}"
      end

      result
    end

    private def analyze_tanstack_file(path : String, result : Array(Endpoint))
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end

        # Extract routes from createFileRoute
        analyze_file_routes(content, path, result)

        # Extract routes from createRoute
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
      # Pattern for createRoute({ path: '/path', ... })
      # Example: const postsRoute = createRoute({ getParentRoute: () => rootRoute, path: '/posts' })
      create_route_pattern = /createRoute\s*\(\s*\{[^}]*path\s*:\s*['"`]([^'"`]+)['"`][^}]*\}/

      content.scan(create_route_pattern) do |match|
        if match.size > 0
          route_path = match[1]
          normalized_path = normalize_path(route_path)

          endpoint = create_endpoint(normalized_path, "GET", path)
          extract_path_parameters(normalized_path, endpoint)
          extract_search_params_from_route_block(content, match[0], endpoint)
          result << endpoint
        end
      end

      # Also handle createRootRoute with path
      root_route_pattern = /createRootRoute\s*\(\s*\{[^}]*path\s*:\s*['"`]([^'"`]+)['"`][^}]*\}/

      content.scan(root_route_pattern) do |match|
        if match.size > 0
          route_path = match[1]
          normalized_path = normalize_path(route_path)

          endpoint = create_endpoint(normalized_path, "GET", path)
          extract_path_parameters(normalized_path, endpoint)
          result << endpoint
        end
      end
    end

    private def normalize_path(path : String) : String
      # TanStack Router uses $param for path parameters
      # Convert to standard :param format
      path.gsub(/\$(\w+)/, ":\\1")
    end

    private def create_endpoint(url : String, method : String, file_path : String) : Endpoint
      endpoint = Endpoint.new(url, method)
      endpoint.details = Details.new(PathInfo.new(file_path, 1))
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

    private def extract_search_params_from_route_block(content : String, route_block : String, endpoint : Endpoint)
      # Extract search params from the route definition block
      extract_search_params(route_block, endpoint)
    end
  end
end
