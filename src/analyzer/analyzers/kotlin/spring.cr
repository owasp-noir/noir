require "../../../models/analyzer"
require "../../../miniparsers/kotlin_route_extractor_ts"
require "../../../miniparsers/kotlin_parameter_extractor_ts"
require "../../../utils/utils.cr"

module Analyzer::Kotlin
  class Spring < Analyzer
    KOTLIN_EXTENSION = "kt"

    def analyze
      webflux_base_path_map = Hash(String, String).new
      dto_builder = Noir::TreeSitterKotlinDtoIndex.new

      file_list = all_files()
      file_list.each do |path|
        next unless File.exists?(path)

        if File.directory?(path)
          process_directory(path, webflux_base_path_map)
        elsif path.ends_with?(".#{KOTLIN_EXTENSION}")
          process_kotlin_file(path, dto_builder, webflux_base_path_map)
        end
      end

      Fiber.yield
      @result
    end

    # Read Spring Webflux base-path + static-locations from
    # `application.yml` / `application.properties` so route paths
    # inherit them and static asset directories show up as GET routes.
    private def process_directory(path : String, webflux_base_path_map : Hash(String, String))
      return unless path.ends_with?("/src")

      webflux_base_path = ""
      static_locations = [] of String

      application_yml_path = File.join(path, "main/resources/application.yml")
      if File.exists?(application_yml_path)
        begin
          config = YAML.parse(File.read(application_yml_path))
          spring = config["spring"]
          if spring
            webflux = spring["webflux"]
            if webflux
              base_path = webflux["base-path"]
              if base_path
                webflux_base_path = base_path.as_s
                webflux_base_path_map[path] = webflux_base_path if webflux_base_path
              end
            end
            resources = spring["resources"] || spring["web"]
            if resources
              if resources["resources"]
                resources = resources["resources"]
              end
              static_locations_yaml = resources["static-locations"]
              if static_locations_yaml
                if static_locations_yaml.as_a?
                  static_locations_yaml.as_a.each do |loc|
                    static_locations << loc.as_s
                  end
                elsif static_locations_yaml.as_s?
                  static_locations_yaml.as_s.split(",").each do |loc|
                    static_locations << loc.strip
                  end
                end
              end
            end
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

          static_locs = properties.match(/spring(\.web)?\.resources\.static-locations\s*=\s*(.*)/)
          if static_locs
            static_locs[2].split(",").each do |loc|
              static_locations << loc.strip
            end
          end
        rescue
          # Handle parsing errors if necessary
        end
      end

      if static_locations.empty?
        static_locations = ["classpath:/META-INF/resources/", "classpath:/resources/", "classpath:/static/", "classpath:/public/"]
      end

      process_static_locations(path, static_locations, webflux_base_path)
    end

    private def process_static_locations(src_path : String, static_locations : Array(String), webflux_base_path : String)
      static_locations.each do |location|
        if location.starts_with?("classpath:")
          resource_path = location.sub("classpath:", "").strip
          full_resource_path = File.join(src_path, "main/resources", resource_path)
          if Dir.exists?(full_resource_path)
            Dir.glob("#{escape_glob_path(full_resource_path)}/**/*") do |file|
              next if File.directory?(file)
              relative_path = file.sub(full_resource_path, "")
              full_url = join_path(webflux_base_path, relative_path)
              @result << Endpoint.new(full_url, "GET", Details.new(PathInfo.new(file)))
            end
          end
        elsif location.starts_with?("file:")
          file_path = location.sub("file:", "").strip
          if Dir.exists?(file_path)
            Dir.glob("#{escape_glob_path(file_path)}/**/*") do |file|
              next if File.directory?(file)
              relative_path = file.sub(file_path, "")
              full_url = join_path(webflux_base_path, relative_path)
              @result << Endpoint.new(full_url, "GET", Details.new(PathInfo.new(file)))
            end
          end
        end
      end
    end

    # Tree-sitter pipeline: route discovery, parameter extraction,
    # `consumes = ...`, and DTO cross-file resolution all run on the
    # vendored Kotlin grammar — no `KotlinParser` / `KotlinLexer`.
    private def process_kotlin_file(path : String, dto_builder : Noir::TreeSitterKotlinDtoIndex, webflux_base_path_map : Hash(String, String))
      content = File.read(path, encoding: "utf-8", invalid: :skip)

      # Skip files without a package declaration — legacy filter that
      # avoids scanning test stubs / throwaway snippets.
      package_name = Noir::TreeSitterKotlinParameterExtractor.extract_package_name(content)
      return if package_name.empty?

      webflux_base_path = find_base_path(path, webflux_base_path_map)
      dto_index = dto_builder.build_for(path, content)

      routes = Noir::TreeSitterKotlinRouteExtractor.extract_routes(content)

      # Pin the parameter format to the FIRST verb seen for each
      # (class, method) — for multi-verb `@RequestMapping(method =
      # [GET, POST])` we want a single shared format so the
      # `params=` constraint expansion matches across both routes
      # (mirrors the legacy `||=` quirk: first verb wins).
      first_verb = Hash(String, String).new
      routes.each do |route|
        key = "#{route.class_name}##{route.method_name}"
        first_verb[key] ||= route.verb
      end

      routes.each do |route|
        key = "#{route.class_name}##{route.method_name}"
        format_verb = first_verb[key]? || route.verb

        parameter_format = Noir::TreeSitterKotlinParameterExtractor.extract_consumes(
          content, route.class_name, route.method_name
        )
        if parameter_format.nil?
          parameter_format = case format_verb
                             when "POST", "PUT", "DELETE", "PATCH"
                               "form"
                             when "GET"
                               "query"
                             end
        end

        parameters = Noir::TreeSitterKotlinParameterExtractor.extract_method_parameters(
          content, route.class_name, route.method_name, format_verb, parameter_format, dto_index
        )

        # Drop the trailing `/` on webflux_base_path when the route
        # path already starts with one, so the join doesn't produce
        # `//`.
        base_path = webflux_base_path
        if base_path.ends_with?("/") && route.path.starts_with?("/")
          base_path = base_path[..-2]
        end

        line = route.line + 1
        details = Details.new(PathInfo.new(path, line))
        @result << Endpoint.new(join_paths(base_path, route.path), route.verb, parameters, details)
      end
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
