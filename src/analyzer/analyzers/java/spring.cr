require "../../../models/analyzer"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../miniparsers/java_parameter_extractor_ts"

module Analyzer::Java
  class Spring < Analyzer
    REGEX_ROUTER_CODE_BLOCK = /route\(\)?.*?\);/m
    REGEX_ROUTE_CODE_LINE   = /((?:andRoute|route)\s*\(|\.)\s*(GET|POST|DELETE|PUT)\(\s*"([^"]*)/

    def analyze
      webflux_base_path_map = Hash(String, String).new
      dto_builder = Noir::TreeSitterJavaDtoIndex.new

      file_list = all_files()
      file_list.each do |path|
        url = ""

        # Extract the Webflux base path from 'application.yml' /
        # 'application.properties' so route paths inherit it.
        if File.directory?(path)
          if path.ends_with?("/src")
            application_yml_path = File.join(path, "main/resources/application.yml")
            if File.exists?(application_yml_path)
              begin
                config = YAML.parse(File.read(application_yml_path))
                spring = config["spring"]
                webflux = spring["webflux"]
                webflux_base_path = webflux["base-path"]

                if webflux_base_path
                  webflux_base_path_map[path] = webflux_base_path.as_s
                end
              rescue
                # Handle parsing errors if necessary
              end
            end

            application_properties_path = File.join(path, "main/resources/application.properties")
            if File.exists?(application_properties_path)
              begin
                properties = File.read(application_properties_path)
                base_path = properties.match(/spring\.webflux\.base-path\s*=\s*(.*)/)
                if base_path
                  webflux_base_path = base_path[1]
                  webflux_base_path_map[path] = webflux_base_path if webflux_base_path
                end
              rescue
                # Handle parsing errors if necessary
              end
            end
          end
        elsif File.exists?(path) && path.ends_with?(".java")
          webflux_base_path = find_base_path(path, webflux_base_path_map)
          content = read_file_content(path)

          # Only files that mention Spring MVC / Feign bindings carry
          # annotation-based routes. Reactive `router().route()` files
          # land in the `else` branch below.
          spring_web_bind_package = "org.springframework.web.bind.annotation."
          feign_client_package = "org.springframework.cloud.openfeign.FeignClient"
          has_spring_bindings = content.includes?(spring_web_bind_package)
          has_feign_bindings = content.includes?(feign_client_package) || content.includes?("@FeignClient")

          if has_spring_bindings || has_feign_bindings
            # Single tree-sitter parse for the whole file — every
            # extraction below pulls from the same root so a
            # controller with N routes pays for 1 parse instead of
            # the previous 4 + 2N. The DTO index, FeignClient
            # detection, route discovery, consumes lookup, and
            # parameter walks all consume `root`.
            Noir::TreeSitter.parse_java(content) do |root|
              # Skip files without a package declaration — legacy filter
              # that avoids scanning test stubs / throwaway snippets.
              package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
              next if package_name.empty?

              dto_index = dto_builder.build_for_with_root(path, content, root)
              feign_clients = Noir::TreeSitterJavaParameterExtractor.extract_feign_client_classes_from(root, content)

              Noir::TreeSitterJavaRouteExtractor.extract_routes_from(root, content).each do |route|
                is_feign_client = feign_clients.includes?(route.class_name)

                parameter_format = Noir::TreeSitterJavaParameterExtractor.extract_consumes_from(
                  root, content, route.class_name, route.method_name
                )
                if parameter_format.nil? && route.verb == "POST"
                  parameter_format = "form"
                end

                parameters = Noir::TreeSitterJavaParameterExtractor.extract_method_parameters_from(
                  root, content, route.class_name, route.method_name, route.verb, parameter_format, dto_index
                )

                # Drop the trailing `/` on webflux_base_path when the
                # route path already starts with one, so the join
                # doesn't produce `//`.
                base_path = webflux_base_path
                if base_path.ends_with?("/") && route.path.starts_with?("/")
                  base_path = base_path[..-2]
                end

                line = route.line + 1
                details = Details.new(PathInfo.new(path, line))

                endpoint = Endpoint.new(
                  join_paths(base_path, route.path), route.verb, parameters, details, is_feign_client
                )
                @result << endpoint
              end
            end
          else
            # Reactive routes declared via `router().route(...).andRoute(...)`
            # — regex-scoped because the builder-pattern shape isn't
            # worth a dedicated tree-sitter walk yet.
            content.scan(REGEX_ROUTER_CODE_BLOCK) do |route_code|
              method_code = route_code[0]
              method_code.scan(REGEX_ROUTE_CODE_LINE) do |match|
                next if match.size != 4
                method = match[2]
                endpoint = match[3].gsub(/\n/, "")
                details = Details.new(PathInfo.new(path))
                @result << Endpoint.new(join_paths(url, endpoint), method, details)
              end
            end
          end
        end
      end
      Fiber.yield

      @result
    end

    def find_base_path(current_path : String, base_paths : Hash(String, String))
      base_paths.keys.sort_by!(&.size).reverse!.each do |path|
        if current_path.starts_with?(path)
          return base_paths[path]
        end
      end

      ""
    end
  end
end
