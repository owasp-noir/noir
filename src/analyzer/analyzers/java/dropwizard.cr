require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/jaxrs_extractor_ts"
require "../../../miniparsers/import_graph"
require "yaml"

module Analyzer::Java
  # Dropwizard ships Jersey under the hood, so JAX-RS resource
  # classes are the routing surface. This analyzer drives the shared
  # `TreeSitterJaxRsExtractor` against files in project roots that
  # carry the `io.dropwizard` marker. Resource classes are often pure
  # JAX-RS and do not import Dropwizard directly.
  class Dropwizard < Analyzer
    JAVA_EXTENSION    = "java"
    DROPWIZARD_MARKER = "io.dropwizard"

    private struct DropwizardPathConfig
      getter application_context_path : String
      getter root_path : String

      def initialize(@application_context_path = "", @root_path = "")
      end

      def base_path : String
        Dropwizard.join_paths(@application_context_path, @root_path)
      end
    end

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      dto_builder = Noir::TreeSitterJavaDtoIndex.new
      bean_cache = Hash(String, Hash(String, Array(Param))).new
      source_cache = Hash(String, String).new

      file_list = all_files()
      path_configs = path_configs_for(file_list)
      dropwizard_roots = dropwizard_project_roots_for(file_list)
      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")
        project_root = project_root_for(path)
        next unless dropwizard_roots.includes?(project_root)

        content = read_file_content(path)

        path_config = path_configs[project_root]? || DropwizardPathConfig.new
        if content.includes?(DROPWIZARD_MARKER)
          extract_asset_bundle_endpoints(content, path_config.application_context_path, path).each do |endpoint|
            @result << endpoint
          end
        end

        # Some Dropwizard files (Application, Module classes) won't
        # carry JAX-RS routes — skip the parse cost when the file
        # has no `jakarta/javax.ws.rs` reference at all.
        next unless content.includes?("jakarta.ws.rs") || content.includes?("javax.ws.rs")

        Noir::TreeSitter.parse_java(content) do |root|
          package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, content)
          next if package_name.empty?

          imports = Noir::TreeSitterJavaParameterExtractor.extract_imports_from(root, content)
          dto_index = dto_builder.build_for_with_root(path, content, root)
          bean_index = bean_index_for(path, content, package_name, bean_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_bean_fields_from(root, content))
          subresource_sources = subresource_sources_for(path, content, package_name, source_cache, imports,
            Noir::TreeSitterJaxRsExtractor.extract_class_names_from(root, content))
          base_path = path_config.base_path

          Noir::TreeSitterJaxRsExtractor.extract_routes_from(root, content, dto_index, bean_index, subresource_sources, include_callees: include_callee).each do |route|
            line = route.line + 1
            details = Details.new(PathInfo.new(route.file_path || path, line))
            endpoint = Endpoint.new(Dropwizard.join_paths(base_path, route.path), route.verb, route.params, details)
            endpoint.protocol = route.protocol
            route.callees.each do |name, callee_line|
              endpoint.push_callee(Callee.new(name, path: route.file_path || path, line: callee_line))
            end
            @result << endpoint
          end
        end
      end

      Fiber.yield
      @result
    end

    def self.join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end

    private def path_configs_for(file_list : Array(String)) : Hash(String, DropwizardPathConfig)
      configs = Hash(String, DropwizardPathConfig).new
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

    private def dropwizard_project_roots_for(file_list : Array(String)) : Set(String)
      roots = Set(String).new

      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        roots << project_root_for(path) if content.includes?(DROPWIZARD_MARKER)
      end

      roots
    end

    private def path_config_for(project_root : String) : DropwizardPathConfig
      config_paths = ([] of String)
      config_paths.concat(Dir.glob(File.join(project_root, "*.yml")))
      config_paths.concat(Dir.glob(File.join(project_root, "*.yaml")))
      config_paths.concat(Dir.glob(File.join(project_root, "config", "*.yml")))
      config_paths.concat(Dir.glob(File.join(project_root, "config", "*.yaml")))
      config_paths.concat(Dir.glob(File.join(project_root, "src/main/resources", "*.yml")))
      config_paths.concat(Dir.glob(File.join(project_root, "src/main/resources", "*.yaml")))

      config_paths.sort.each do |config_path|
        config = read_path_config(config_path)
        return config unless config.base_path.empty?
      end

      DropwizardPathConfig.new
    end

    private def read_path_config(path : String) : DropwizardPathConfig
      root = YAML.parse(File.read(path))
      server = root["server"]?
      return DropwizardPathConfig.new unless server

      server_type = yaml_string(server, "type")
      application_context_path = normalize_path(yaml_string(server, "applicationContextPath"))
      application_context_path = "/application" if application_context_path.empty? && server_type == "simple"
      root_path = normalize_root_path(yaml_string(server, "rootPath"))

      DropwizardPathConfig.new(application_context_path, root_path)
    rescue
      DropwizardPathConfig.new
    end

    private def yaml_string(node : YAML::Any, key : String) : String?
      node[key]?.try(&.as_s?)
    end

    private def normalize_path(path : String?) : String
      return "" unless path

      trimmed = path.strip
      return "" if trimmed.empty? || trimmed == "/"
      trimmed.starts_with?("/") ? trimmed : "/#{trimmed}"
    end

    private def normalize_root_path(path : String?) : String
      return "" unless path

      normalized = normalize_path(path)
      normalized = normalized.chomp('*').rstrip('/')
      return "" if normalized.empty? || normalized == "/"
      normalized
    end

    private def project_root_for(path : String) : String
      marker = "/src/main/java/"
      if index = path.index(marker)
        path[...index]
      else
        File.dirname(path)
      end
    end

    private def bean_index_for(path : String,
                               content : String,
                               package_name : String,
                               cache : Hash(String, Hash(String, Array(Param))),
                               imports : Array(Noir::ImportGraph::ImportRef)? = nil,
                               current_file_beans : Hash(String, Array(Param))? = nil) : Hash(String, Array(Param))
      result = Hash(String, Array(Param)).new
      resolved_imports = imports || Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, resolved_imports, JAVA_EXTENSION) do |file|
        beans = cache[file] ||= begin
          if file == path && current_file_beans
            current_file_beans
          else
            body = file == path ? content : read_file_content(file)
            Noir::TreeSitterJaxRsExtractor.extract_bean_fields(body)
          end
        rescue File::NotFoundError
          {} of String => Array(Param)
        end

        beans.each { |name, params| result[name] ||= params }
      end

      result
    end

    private def subresource_sources_for(path : String,
                                        content : String,
                                        package_name : String,
                                        cache : Hash(String, String),
                                        imports : Array(Noir::ImportGraph::ImportRef)? = nil,
                                        current_file_class_names : Array(String)? = nil) : Hash(String, Noir::TreeSitterJaxRsExtractor::SourceEntry)
      result = Hash(String, Noir::TreeSitterJaxRsExtractor::SourceEntry).new
      resolved_imports = imports || Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, resolved_imports, JAVA_EXTENSION) do |file|
        body = cache[file] ||= begin
          file == path ? content : read_file_content(file)
        rescue File::NotFoundError
          ""
        end
        next if body.empty?
        next unless body.includes?("jakarta.ws.rs") || body.includes?("javax.ws.rs")

        class_names = file == path && current_file_class_names ? current_file_class_names : Noir::TreeSitterJaxRsExtractor.extract_class_names(body)
        class_names.each do |name|
          result[name] ||= {file, body}
        end
      end

      result
    end

    private def extract_asset_bundle_endpoints(content : String, application_context_path : String, path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      return endpoints unless content.includes?("AssetsBundle")

      content.scan(/new\s+AssetsBundle\s*\(([^)]*)\)/m) do |match|
        args = split_top_level_args(match[1])
        uri_path = asset_bundle_uri_path(args)
        next if uri_path.empty?

        line = line_for_offset(content, match.begin(0) || 0)
        endpoint_path = asset_bundle_endpoint_path(application_context_path, uri_path)
        details = Details.new(PathInfo.new(path, line))
        next if endpoints.any? { |endpoint| endpoint.url == endpoint_path && endpoint.method == "GET" }

        endpoints << Endpoint.new(endpoint_path, "GET", details)
      end

      endpoints
    end

    private def asset_bundle_uri_path(args : Array(String)) : String
      return "/assets" if args.empty?

      raw_path = if args.size >= 2
                   string_literal_value(args[1])
                 else
                   string_literal_value(args[0])
                 end
      return "" unless raw_path

      normalize_path(raw_path)
    end

    private def asset_bundle_endpoint_path(application_context_path : String, uri_path : String) : String
      base = Dropwizard.join_paths(application_context_path, uri_path)
      base = "/" if base.empty?
      base == "/" ? "/*" : "#{base.rstrip('/')}/*"
    end

    private def split_top_level_args(source : String) : Array(String)
      args = [] of String
      current = String::Builder.new
      depth = 0
      quote : Char? = nil
      escaped = false

      source.each_char do |char|
        if quote
          current << char
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            quote = nil
          end
          next
        end

        case char
        when '"', '\''
          quote = char
          current << char
        when '(', '{', '['
          depth += 1
          current << char
        when ')', '}', ']'
          depth -= 1 if depth > 0
          current << char
        when ','
          if depth == 0
            args << current.to_s.strip
            current = String::Builder.new
          else
            current << char
          end
        else
          current << char
        end
      end

      tail = current.to_s.strip
      args << tail unless tail.empty?
      args
    end

    private def string_literal_value(expression : String) : String?
      if match = expression.strip.match(/\A["']([^"']*)["']\z/)
        match[1]
      end
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      content[0...offset].count('\n') + 1
    end
  end
end
