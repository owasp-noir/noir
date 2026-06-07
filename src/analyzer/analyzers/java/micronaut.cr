require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/micronaut_extractor_ts"
require "yaml"

module Analyzer::Java
  class Micronaut < Analyzer
    JAVA_EXTENSION    = "java"
    MICRONAUT_MARKERS = ["io.micronaut", "micronaut.io"]
    alias PackageScopeKey = Tuple(String, String)

    private struct MicronautPathConfig
      getter context_path : String
      getter static_resource_mappings : Array(String)

      def initialize(@context_path = "", @static_resource_mappings = [] of String)
      end
    end

    private struct MicronautInterfaceRouteEntry
      getter route : Noir::TreeSitterMicronautExtractor::Route
      getter path : String
      getter source : String
      getter package_name : String

      def initialize(@route, @path, @source, @package_name)
      end
    end

    private struct MicronautInterfaceRouteIndex
      getter by_package : Hash(PackageScopeKey, Hash(String, Array(MicronautInterfaceRouteEntry)))
      getter by_fqcn : Hash(PackageScopeKey, Array(MicronautInterfaceRouteEntry))

      def initialize
        @by_package = Hash(PackageScopeKey, Hash(String, Array(MicronautInterfaceRouteEntry))).new
        @by_fqcn = Hash(PackageScopeKey, Array(MicronautInterfaceRouteEntry)).new
      end

      def add(project_root : String, package_name : String, interface_name : String, entry : MicronautInterfaceRouteEntry)
        package_routes = @by_package[{project_root, package_name}] ||= Hash(String, Array(MicronautInterfaceRouteEntry)).new
        package_routes[interface_name] ||= [] of MicronautInterfaceRouteEntry
        package_routes[interface_name] << entry

        unless package_name.empty?
          key = {project_root, "#{package_name}.#{interface_name}"}
          @by_fqcn[key] ||= [] of MicronautInterfaceRouteEntry
          @by_fqcn[key] << entry
        end
      end
    end

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      dto_builder = Noir::TreeSitterJavaDtoIndex.new

      file_list = all_files()
      path_configs = path_configs_for(file_list)
      interface_route_index = collect_interface_route_index(file_list, dto_builder, include_callee)

      path_configs.each do |_project_root, config|
        config.static_resource_mappings.each do |mapping|
          @result << Endpoint.new(join_paths(config.context_path, mapping), "GET")
        end
      end

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless MICRONAUT_MARKERS.any? { |marker| content.includes?(marker) }

        package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name(content)
        next if package_name.empty?

        dto_index = dto_builder.build_for(path, content)
        imports = java_imports(content)
        base_path = (path_configs[project_root_for(path)]? || MicronautPathConfig.new).context_path

        Noir::TreeSitterMicronautExtractor.extract_routes(content, dto_index, include_callees: include_callee).each do |route|
          line = route.line + 1
          details = Details.new(PathInfo.new(path, line))
          endpoint = Endpoint.new(join_paths(base_path, route.path), route.verb, route.params, details)
          endpoint.protocol = route.protocol
          route.callees.each do |(name, callee_line)|
            endpoint.push_callee(Callee.new(name, path: path, line: callee_line))
          end
          @result << endpoint
        end

        Noir::TreeSitterMicronautExtractor.extract_controller_interface_implementations(content).each do |implementation|
          implementation.interface_names.each do |interface_name|
            visible_interface_routes(interface_route_index, path, package_name, imports, interface_name).each do |entry|
              entry_route = entry.route
              implementation.paths.each do |implementation_path|
                inherited_path = join_paths(implementation_path, entry_route.path)
                details = Details.new(PathInfo.new(entry.path, entry_route.line + 1))
                endpoint = Endpoint.new(join_paths(base_path, inherited_path), entry_route.verb, entry_route.params, details)
                endpoint.protocol = entry_route.protocol
                entry_route.callees.each do |name, callee_line|
                  endpoint.push_callee(Callee.new(name, path: entry.path, line: callee_line))
                end
                @result << endpoint
              end
            end
          end
        end
      end

      Fiber.yield
      @result
    end

    private def collect_interface_route_index(file_list : Array(String),
                                              dto_builder : Noir::TreeSitterJavaDtoIndex,
                                              include_callee : Bool) : MicronautInterfaceRouteIndex
      index = MicronautInterfaceRouteIndex.new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless MICRONAUT_MARKERS.any? { |marker| content.includes?(marker) }

        package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name(content)
        next if package_name.empty?

        dto_index = dto_builder.build_for(path, content)
        Noir::TreeSitterMicronautExtractor.extract_interface_routes(content, dto_index, include_callees: include_callee).each do |interface_name, routes|
          routes.each do |route|
            index.add(project_root_for(path), package_name, interface_name, MicronautInterfaceRouteEntry.new(route, path, content, package_name))
          end
        end
      end

      index
    end

    private def visible_interface_routes(index : MicronautInterfaceRouteIndex,
                                         path : String,
                                         package_name : String,
                                         imports : Array(String),
                                         interface_name : String) : Array(MicronautInterfaceRouteEntry)
      routes = [] of MicronautInterfaceRouteEntry
      seen = Set(String).new
      project_root = project_root_for(path)

      add_interface_routes(routes, seen, index.by_package[{project_root, package_name}]?.try(&.[interface_name]?))

      imports.each do |import_name|
        if import_name.ends_with?(".*")
          add_interface_routes(routes, seen, index.by_package[{project_root, import_name[...-2]}]?.try(&.[interface_name]?))
        elsif import_name.ends_with?(".#{interface_name}")
          add_interface_routes(routes, seen, index.by_fqcn[{project_root, import_name}]?)
        end
      end

      routes
    end

    private def add_interface_routes(target : Array(MicronautInterfaceRouteEntry),
                                     seen : Set(String),
                                     routes : Array(MicronautInterfaceRouteEntry)?)
      return unless routes

      routes.each do |entry|
        route = entry.route
        key = "#{entry.path}:#{route.class_name}:#{route.method_name}:#{route.verb}:#{route.path}"
        next if seen.includes?(key)
        seen << key
        target << entry
      end
    end

    private def java_imports(content : String) : Array(String)
      imports = [] of String
      content.scan(/^\s*import\s+(?!static\s)([A-Za-z_][A-Za-z0-9_.]*(?:\.\*)?)\s*;/m) do |match|
        imports << match[1]
      end
      imports
    end

    private def path_configs_for(file_list : Array(String)) : Hash(String, MicronautPathConfig)
      configs = Hash(String, MicronautPathConfig).new
      project_roots = Set(String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        project_roots << project_root_for(path)
      end

      project_roots.each do |root|
        configs[root] = path_config_for(root)
      end

      configs
    end

    private def path_config_for(project_root : String) : MicronautPathConfig
      values = Hash(String, String).new

      resource_dirs_for(project_root).each do |dir|
        properties_path = File.join(dir, "application.properties")
        values.merge!(read_properties(properties_path)) if File.exists?(properties_path)

        yml_path = File.join(dir, "application.yml")
        yaml_path = File.join(dir, "application.yaml")
        merge_yaml_path_config(values, yml_path) if File.exists?(yml_path)
        merge_yaml_path_config(values, yaml_path) if File.exists?(yaml_path)
      end

      MicronautPathConfig.new(
        normalize_optional_path(values["micronaut.server.context-path"]?),
        static_resource_mappings(values)
      )
    end

    private def resource_dirs_for(project_root : String) : Array(String)
      [
        File.join(project_root, "src/main/resources"),
        File.join(project_root, "resources"),
        project_root,
      ].uniq
    end

    private def read_properties(path : String) : Hash(String, String)
      values = Hash(String, String).new
      File.each_line(path) do |line|
        stripped = line.strip
        next if stripped.empty? || stripped.starts_with?("#") || stripped.starts_with?("!")

        if separator = stripped.index(/[=:]/)
          key = stripped[...separator].strip
          value = stripped[(separator + 1)..].strip
          values[key] = value unless key.empty?
        end
      end
      values
    end

    private def merge_yaml_path_config(values : Hash(String, String), path : String)
      flatten_yaml_values(values, YAML.parse(File.read(path)))
    rescue
      nil
    end

    private def flatten_yaml_values(values : Hash(String, String), node : YAML::Any, prefix = [] of String)
      if hash = node.as_h?
        hash.each do |key, value|
          flatten_yaml_values(values, value, prefix + [key.to_s])
        end
      elsif array = node.as_a?
        values[prefix.join(".")] = array.map(&.to_s).join(",") unless prefix.empty?
      elsif !prefix.empty?
        values[prefix.join(".")] = node.to_s
      end
    end

    private def static_resource_mappings(values : Hash(String, String)) : Array(String)
      mappings = [] of String

      values.each do |key, value|
        next unless key.starts_with?("micronaut.router.static-resources.")
        next unless key.ends_with?(".mapping")

        name = key["micronaut.router.static-resources.".size...-".mapping".size]
        enabled = values["micronaut.router.static-resources.#{name}.enabled"]?
        next if enabled && enabled.strip.downcase == "false"

        mapping = normalize_static_mapping(value)
        next if mapping.empty?
        next if mappings.includes?(mapping)

        mappings << mapping
      end

      mappings
    end

    private def normalize_static_mapping(mapping : String) : String
      normalized = mapping.strip
      return "" if normalized.empty?

      normalized.starts_with?("/") ? normalized : "/#{normalized}"
    end

    private def project_root_for(path : String) : String
      marker = "/src/main/java/"
      if index = path.index(marker)
        path[...index]
      else
        File.dirname(path)
      end
    end

    private def normalize_optional_path(path : String?) : String
      return "" unless path

      trimmed = path.strip
      return "" if trimmed.empty? || trimmed == "/"
      trimmed.starts_with?("/") ? trimmed : "/#{trimmed}"
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
