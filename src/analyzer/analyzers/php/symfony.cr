require "../../engines/php_engine"

module Analyzer::Php
  class Symfony < PhpEngine
    private struct ClassRoutePrefix
      getter path, body_start, body_end

      def initialize(@path : String, @body_start : Int32, @body_end : Int32)
      end
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # Analyze PHP controller files
      if path.ends_with?(".php")
        endpoints.concat(analyze_php_routes(path, include_callee))
      end

      # Analyze YAML route files
      if path.ends_with?(".yaml") || path.ends_with?(".yml")
        if path.includes?("config") && (path.includes?("routes") || path.includes?("routing"))
          endpoints.concat(analyze_yaml_routes(path))
        end
      end

      endpoints
    end

    private def analyze_php_routes(path : String, include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        class_prefixes = extract_class_route_prefixes(content)

        # Look for route annotations (@Route) - more flexible pattern
        # Track offset to find each match correctly
        offset = 0
        content.scan(/@Route\s*\((.*?)\)/m) do |match|
          route_path = extract_symfony_route_path(match[1])
          next unless route_path

          full_match = match[0]

          # Find this specific match starting from current offset
          route_start = content.index(full_match, offset)
          if route_start
            offset = route_start + full_match.size
            next if route_applies_to_class?(content, offset)

            # Extract methods from the annotation itself
            methods = extract_methods_from_symfony_context(full_match)
            methods = ["GET"] if methods.empty?

            method_body = extract_php_method_body_after(content, route_start)

            full_path = build_full_path(class_prefix_for_position(class_prefixes, route_start), route_path)
            params = extract_brace_path_params(full_path)
            # Extract additional parameters from method body
            params.concat(extract_method_params(method_body[0])) if method_body

            details = Details.new(PathInfo.new(path))

            methods.each do |method|
              endpoint = Endpoint.new(full_path, method.upcase, params, details)
              attach_method_callees(endpoint, method_body, path) if include_callee
              endpoints << endpoint
            end
          end
        end

        # Look for route attributes (#[Route]) - PHP 8 style
        # Track offset to find each match correctly
        offset = 0
        content.scan(/#\[Route\s*\((.*?)\)\]/m) do |match|
          route_path = extract_symfony_route_path(match[1])
          next unless route_path

          full_match = match[0]

          # Find this specific match starting from current offset
          route_start = content.index(full_match, offset)
          if route_start
            offset = route_start + full_match.size
            next if route_applies_to_class?(content, offset)

            # Extract methods from the attribute itself
            methods = extract_methods_from_symfony_context(full_match)
            methods = ["GET"] if methods.empty?

            method_body = extract_php_method_body_after(content, route_start)

            full_path = build_full_path(class_prefix_for_position(class_prefixes, route_start), route_path)
            params = extract_brace_path_params(full_path)
            # Extract additional parameters from method body
            params.concat(extract_method_params(method_body[0])) if method_body

            details = Details.new(PathInfo.new(path))

            methods.each do |method|
              endpoint = Endpoint.new(full_path, method.upcase, params, details)
              attach_method_callees(endpoint, method_body, path) if include_callee
              endpoints << endpoint
            end
          end
        end
      end

      endpoints
    end

    private def extract_class_route_prefixes(content : String) : Array(ClassRoutePrefix)
      prefixes = [] of ClassRoutePrefix
      class_regex = /\bclass\s+\w+[^{]*\{/m
      offset = 0

      while class_match = content.match(class_regex, offset)
        class_start = class_match.begin(0)
        brace_pos = class_match.end(0) - 1
        class_end = find_matching_php_close_brace(content, brace_pos)
        if class_end
          prefix = route_prefix_before_class(content, class_start)
          prefixes << ClassRoutePrefix.new(prefix, brace_pos + 1, class_end) if prefix
          offset = class_end + 1
        else
          offset = class_match.end(0)
        end
      end

      prefixes
    end

    private def route_prefix_before_class(content : String, class_start : Int32) : String?
      lookbehind_start = Math.max(0, class_start - 600)
      prelude = content[lookbehind_start...class_start]

      if attribute_match = prelude.match(/#\[Route\s*\((.*?)\)\]\s*$/m)
        return extract_symfony_route_path(attribute_match[1])
      end

      if annotation_match = prelude.match(/@Route\s*\((.*?)\).*?\*\/\s*$/m)
        return extract_symfony_route_path(annotation_match[1])
      end

      nil
    end

    private def route_applies_to_class?(content : String, route_end : Int32) : Bool
      next_target = content.match(/\b(class|function)\b/m, route_end)
      return false unless next_target

      next_target[1] == "class"
    end

    private def class_prefix_for_position(prefixes : Array(ClassRoutePrefix), pos : Int32) : String
      prefix = prefixes.find { |class_prefix| pos >= class_prefix.body_start && pos < class_prefix.body_end }
      prefix ? prefix.path : ""
    end

    private def extract_symfony_route_path(context : String) : String?
      # `path:` / `path =` as a standalone key. A multi-line `#[Route(\n  path:
      # '/x',\n  …)]` puts `path` after a newline+indent, which the old
      # `(?:^|[,(]\s*)` anchor missed — so every multi-line route attribute
      # (Shopware's whole storefront) was dropped. A negative-lookbehind on a
      # word char accepts any non-word boundary (start, comma, paren, newline,
      # space) while still rejecting `subpath:` / `routePath:`.
      if path_match = context.match(/(?<!\w)path\s*[:=]\s*['"]([^'"]+)['"]/i)
        return path_match[1]
      end

      if path_match = context.match(/^\s*['"]([^'"]+)['"]/)
        return path_match[1]
      end

      nil
    end

    private def extract_methods_from_symfony_context(context : String) : Array(String)
      methods = [] of String

      if match = context.match(/methods\s*[:=]\s*\[([^\]]+)\]/m)
        methods.concat(extract_method_tokens(match[1]))
      elsif match = context.match(/methods\s*=\s*\{([^}]+)\}/m)
        methods.concat(extract_method_tokens(match[1]))
      elsif match = context.match(/methods\s*[:=]\s*['"]([^'"]+)['"]/)
        methods << match[1].upcase
      elsif match = context.match(/methods\s*[:=]\s*(?:[\w\\]+::)?METHOD_(\w+)/i)
        methods << match[1].upcase
      end

      methods.uniq
    end

    # Methods inside a `methods: [...]` / `={...}` list — either string
    # literals (`'POST'`) or Symfony's `Request::METHOD_POST` constants (used
    # heavily by Shopware), which the string scan alone would have missed and
    # silently defaulted to GET.
    private def extract_method_tokens(list : String) : Array(String)
      tokens = [] of String
      list.scan(/['"]([^'"]+)['"]/) { |m| tokens << m[1].upcase }
      list.scan(/METHOD_(\w+)/i) { |m| tokens << m[1].upcase }
      tokens
    end

    private def extract_methods_from_annotation_context(context : String) : Array(String)
      extract_methods_from_symfony_context(context)
    end

    private def extract_methods_from_attribute_context(context : String) : Array(String)
      extract_methods_from_symfony_context(context)
    end

    private def analyze_yaml_routes(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint

      begin
        File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
          content = file.gets_to_end

          # Simple YAML route parsing for Symfony
          # Look for patterns like:
          # route_name:
          #   path: /api/users/{id}
          #   methods: [GET, POST]

          yaml = YAML.parse(content)
          if routes = yaml.as_h?
            routes.each_value do |route|
              route_h = route.as_h?
              next unless route_h

              route_path = route_h[YAML::Any.new("path")]?.try(&.as_s?)
              next unless route_path

              methods = extract_yaml_methods(route_h[YAML::Any.new("methods")]?)
              methods = ["GET"] if methods.empty?

              params = extract_brace_path_params(route_path)
              details = Details.new(PathInfo.new(path))

              methods.each do |method|
                endpoints << Endpoint.new(route_path, method.upcase, params, details)
              end
            end
          end
        end
      rescue e
        logger.debug "Error parsing YAML routes in #{path}: #{e}"
      end

      endpoints
    end

    private def extract_yaml_methods(node : YAML::Any?) : Array(String)
      return [] of String unless node

      if methods = node.as_a?
        methods.compact_map(&.as_s?).reject(&.empty?)
      elsif method = node.as_s?
        method.empty? ? [] of String : [method]
      else
        [] of String
      end
    end

    private def attach_method_callees(endpoint : Endpoint, method_body : Tuple(String, Int32)?, path : String)
      return unless method_body

      body, start_line = method_body
      callees = Noir::PhpCalleeExtractor.callees_for_body(body, path, start_line)
      attach_php_callees(endpoint, callees)
    end

    private def extract_method_params(method_body : String) : Array(Param)
      params = [] of Param
      seen_params = Set(String).new

      # Extract query parameters: $request->query->get('param')
      query_matches = method_body.scan(/\$request->query->get\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/)
      query_matches.each do |match|
        param_name = match[1]
        unless seen_params.includes?(param_name)
          params << Param.new(param_name, "", "query")
          seen_params.add(param_name)
        end
      end

      # Extract request body/form parameters: $request->request->get('param')
      request_matches = method_body.scan(/\$request->request->get\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/)
      request_matches.each do |match|
        param_name = match[1]
        unless seen_params.includes?(param_name)
          params << Param.new(param_name, "", "form")
          seen_params.add(param_name)
        end
      end

      # Extract header parameters: $request->headers->get('param')
      header_matches = method_body.scan(/\$request->headers->get\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/)
      header_matches.each do |match|
        param_name = match[1]
        unless seen_params.includes?(param_name)
          params << Param.new(param_name, "", "header")
          seen_params.add(param_name)
        end
      end

      # Extract cookie parameters: $request->cookies->get('param')
      cookie_matches = method_body.scan(/\$request->cookies->get\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/)
      cookie_matches.each do |match|
        param_name = match[1]
        unless seen_params.includes?(param_name)
          params << Param.new(param_name, "", "cookie")
          seen_params.add(param_name)
        end
      end

      # Extract file parameters: $request->files->get('param')
      file_matches = method_body.scan(/\$request->files->get\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/)
      file_matches.each do |match|
        param_name = match[1]
        unless seen_params.includes?(param_name)
          params << Param.new(param_name, "", "file")
          seen_params.add(param_name)
        end
      end

      # Extract generic request parameters: $request->get('param')
      # This is ambiguous (could be query or body), so we mark it as query by default
      generic_matches = method_body.scan(/\$request->get\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*[^)]+)?\)/)
      generic_matches.each do |match|
        param_name = match[1]
        unless seen_params.includes?(param_name)
          params << Param.new(param_name, "", "query")
          seen_params.add(param_name)
        end
      end

      params
    end
  end
end
