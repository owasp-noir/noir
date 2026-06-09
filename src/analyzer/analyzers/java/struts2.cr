require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/java_callee_extractor"
require "../../../miniparsers/java_parameter_extractor_ts"
require "xml"

module Analyzer::Java
  class Struts2 < Analyzer
    STRUTS_CONFIG_BASENAMES = Set{"struts.xml", "struts-plugin.xml", "struts-deferred.xml"}
    DEFAULT_LOCATORS        = ["action", "actions", "struts", "struts2"]
    REST_METHODS            = {
      "index"         => {"GET", ""},
      "show"          => {"GET", "/:id"},
      "edit"          => {"GET", "/:id/edit"},
      "editNew"       => {"GET", "/new"},
      "deleteConfirm" => {"GET", "/:id/deleteConfirm"},
      "create"        => {"POST", ""},
      "update"        => {"PUT", "/:id"},
      "destroy"       => {"DELETE", "/:id"},
    }

    private struct XmlAction
      getter name : String
      getter method_name : String
      getter line : Int32?
      getter class_name : String

      def initialize(@name, @method_name, @line, @class_name = "")
      end
    end

    private struct XmlPackage
      getter name : String
      getter namespace : String?
      getter extends_names : Array(String)
      getter actions : Array(XmlAction)

      def initialize(@name, @namespace, @extends_names, @actions)
      end
    end

    private class ConventionConfig
      property action_suffixes : Array(String)
      property locators : Array(String)
      property action_packages : Array(String)
      property? rest_enabled : Bool

      def initialize
        @action_suffixes = ["Action"]
        @locators = DEFAULT_LOCATORS.dup
        @action_packages = [] of String
        @rest_enabled = false
      end
    end

    private struct JavaClass
      getter name : String
      getter package_name : String
      getter annotations : String
      getter header : String
      getter body : String
      getter body_offset : Int32
      getter line : Int32
      getter? abstract : Bool

      def initialize(@name, @package_name, @annotations, @header, @body, @body_offset, @line, @abstract)
      end
    end

    private struct JavaMethod
      getter name : String
      getter annotations : String
      getter line : Int32

      def initialize(@name, @annotations, @line)
      end
    end

    alias ScopedNameKey = Tuple(String, String)

    @include_callee : Bool = false
    @handler_index : Hash(ScopedNameKey, String) = {} of ScopedNameKey => String

    def analyze
      @include_callee = callees_needed?
      file_list = all_files()
      config_files = struts_config_files(file_list)
      convention_configs = Hash(String, ConventionConfig).new { |hash, key| hash[key] = ConventionConfig.new }
      seen = Set(String).new

      java_files = file_list.select do |path|
        File.exists?(path) && path.ends_with?(".java") && !JavaEngine.test_path?(path)
      end

      # Build a FQCN → source-path index up front so XML `<action
      # class="…">` handlers can be resolved for callee extraction. Only
      # needed when callee/ai-context enrichment is requested.
      build_handler_index(java_files) if @include_callee

      config_files.each do |path|
        parse_struts_config(path, file_list, convention_configs[configured_base_for(path)], seen)
      end

      package_annotations = package_annotations_for(java_files)

      java_files.each do |path|
        analyze_java_file(path, convention_configs[configured_base_for(path)], package_annotations)
      end

      Fiber.yield
      @result
    end

    # Index every top-level Java class by its fully-qualified name so an
    # XML-configured `<action class="…">` can be resolved back to its
    # source file for callee extraction. Regex-based to stay cheap; the
    # index is only built when callee/ai-context enrichment is on.
    private def build_handler_index(java_files : Array(String))
      java_files.each do |path|
        content = read_file_content(path)
        package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name(content)
        content.scan(/(?:^|\n)\s*(?:public\s+|protected\s+|private\s+|abstract\s+|final\s+|static\s+)*class\s+([A-Za-z_][A-Za-z0-9_]*)/m) do |match|
          class_name = match[1]
          fqcn = package_name.empty? ? class_name : "#{package_name}.#{class_name}"
          @handler_index[{configured_base_for(path), fqcn}] ||= path
        end
      rescue e : Exception
        @logger.debug "Failed to index Struts handler #{path}: #{e.message}"
      end
    end

    # 1-hop callees for an XML-configured action by resolving its
    # `class`/`method` (default `execute`) to the handler source. Returns
    # empty unless enrichment is on and the handler file is indexed.
    private def xml_action_callees(action : XmlAction, config_path : String) : Array(Callee)
      callees = [] of Callee
      return callees unless @include_callee
      return callees if action.class_name.empty?

      handler_path = @handler_index[{configured_base_for(config_path), action.class_name}]?
      return callees unless handler_path && File.exists?(handler_path)

      simple_name = action.class_name.split('.').last
      method_name = action.method_name.empty? ? "execute" : action.method_name
      handler_content = read_file_content(handler_path)

      Noir::TreeSitter.parse_java(handler_content) do |root|
        Noir::JavaCalleeExtractor.callees_in_method(root, handler_content, handler_path, simple_name, method_name).each do |entry|
          name, callee_path, callee_line = entry
          callees << Callee.new(name, path: callee_path, line: callee_line)
        end
      end
      callees
    rescue e : Exception
      @logger.debug "Failed to extract Struts XML callees for #{action.class_name}: #{e.message}"
      [] of Callee
    end

    private def struts_config_files(file_list : Array(String)) : Array(String)
      file_list.select do |path|
        next false unless File.exists?(path)
        next false unless path.ends_with?(".xml")
        # Test-source Struts config (`src/test/resources/struts.xml`,
        # `src/it/...`) exercises the framework itself and never backs a
        # deployed action — gate it the same way the `.java` selection at
        # the top of `analyze` does via the shared `JavaEngine.test_path?`
        # convention.
        next false if JavaEngine.test_path?(path)
        basename = File.basename(path)
        STRUTS_CONFIG_BASENAMES.includes?(basename) || basename.ends_with?("-struts.xml")
      end
    end

    private def parse_struts_config(path : String,
                                    file_list : Array(String),
                                    convention_config : ConventionConfig,
                                    seen : Set(String))
      expanded = File.expand_path(path)
      return if seen.includes?(expanded)
      seen << expanded

      content = read_file_content(path)
      doc = XML.parse(content)
      root = find_xml_child(doc, "struts") || doc.first_element_child
      return unless root && root.name == "struts"

      collect_constants(root, convention_config)
      collect_includes(root, path, file_list).each do |include_path|
        parse_struts_config(include_path, file_list, convention_config, seen)
      end

      packages = collect_packages(root, content)
      packages.each_value do |package_config|
        namespace = package_namespace(package_config, packages, Set(String).new)
        package_config.actions.each do |action|
          add_route(join_paths(namespace, normalize_action_pattern(action.name)), "ANY", path, action.line,
            callees: xml_action_callees(action, path))
        end
      end
    rescue e : Exception
      @logger.debug "Failed to parse Struts config #{path}: #{e.message}"
    end

    private def collect_constants(root : XML::Node, config : ConventionConfig)
      each_xml_child(root, "constant") do |node|
        name = xml_attr(node, "name")
        value = xml_attr(node, "value")
        next if name.empty? || value.empty?

        case name
        when "struts.convention.action.suffix"
          config.action_suffixes = (split_csv(value).reject(&.empty?) + ["Action"]).uniq
        when "struts.convention.package.locators"
          config.locators = split_csv(value).reject(&.empty?)
        when "struts.convention.action.packages"
          config.action_packages = split_csv(value).reject(&.empty?)
        when "struts.convention.default.parent.package"
          config.rest_enabled = true if value == "rest-default"
        end
      end
    end

    private def collect_includes(root : XML::Node, current_path : String, file_list : Array(String)) : Array(String)
      includes = [] of String
      each_xml_child(root, "include") do |node|
        include_name = xml_attr(node, "file")
        next if include_name.empty?

        if include_path = resolve_include_path(include_name, current_path, file_list)
          includes << include_path
        end
      end
      includes
    end

    private def resolve_include_path(include_name : String, current_path : String, file_list : Array(String)) : String?
      candidates = [] of String
      candidates << include_name if include_name.starts_with?("/")
      candidates << File.expand_path(include_name, File.dirname(current_path))
      candidates << File.join(configured_base_for(current_path), include_name.lstrip('/'))

      if found = candidates.find { |candidate| File.exists?(candidate) }
        return found
      end

      normalized = include_name.lstrip('/')
      base = configured_base_for(current_path)
      scoped_files = base.empty? ? file_list : file_list.select { |path| path_under_root?(path, base) }
      scoped_files.find { |path| path.ends_with?("/#{normalized}") || File.basename(path) == File.basename(include_name) }
    end

    private def collect_packages(root : XML::Node, content : String) : Hash(String, XmlPackage)
      packages = Hash(String, XmlPackage).new
      each_xml_child(root, "package") do |node|
        name = xml_attr(node, "name")
        next if name.empty?

        namespace = node["namespace"]?
        extends_names = split_csv(xml_attr(node, "extends"))
        # Anchor action-line lookups to this package's offset so that an
        # action name shared across packages (e.g. `delete` in both
        # `/skill` and `/employee`) resolves to the declaration inside
        # the owning package rather than the document's first match.
        package_offset = package_start_offset(content, name)
        actions = [] of XmlAction
        each_xml_child(node, "action") do |action_node|
          action_name = xml_attr(action_node, "name")
          next if action_name.empty?
          actions << XmlAction.new(action_name, xml_attr(action_node, "method"),
            xml_line_for(content, action_name, package_offset), xml_attr(action_node, "class"))
        end

        packages[name] = XmlPackage.new(name, namespace, extends_names, actions)
      end
      packages
    end

    private def package_namespace(package_config : XmlPackage,
                                  packages : Hash(String, XmlPackage),
                                  seen : Set(String)) : String
      if namespace = package_config.namespace
        return normalize_namespace(namespace)
      end
      return "" if seen.includes?(package_config.name)
      seen << package_config.name

      package_config.extends_names.each do |parent_name|
        if parent = packages[parent_name]?
          inherited = package_namespace(parent, packages, seen)
          return inherited unless inherited.empty?
        end
      end

      ""
    end

    private def package_annotations_for(java_files : Array(String)) : Hash(ScopedNameKey, String)
      package_annotations = Hash(ScopedNameKey, String).new
      java_files.each do |path|
        next unless File.basename(path) == "package-info.java"

        content = read_file_content(path)
        package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name(content)
        next if package_name.empty?

        if package_index = content.index(/\bpackage\s+#{Regex.escape(package_name)}\s*;/)
          annotations = annotations_before(content, package_index)
          package_annotations[{configured_base_for(path), package_name}] = annotations unless annotations.empty?
        end
      rescue e : Exception
        @logger.debug "Failed to parse Struts package annotations #{path}: #{e.message}"
      end
      package_annotations
    end

    private def analyze_java_file(path : String,
                                  config : ConventionConfig,
                                  package_annotations : Hash(ScopedNameKey, String))
      content = read_file_content(path)
      return unless struts_java_source?(content, config)

      # When callee/ai-context enrichment is requested, parse the file
      # once with tree-sitter and reuse the root for every action route
      # in the file. On a default scan we skip the parse entirely.
      if @include_callee
        Noir::TreeSitter.parse_java(content) do |root|
          analyze_java_classes(path, config, package_annotations, content, root)
        end
      else
        analyze_java_classes(path, config, package_annotations, content, nil)
      end
    rescue e : Exception
      @logger.debug "Failed to parse Struts Java source #{path}: #{e.message}"
    end

    private def analyze_java_classes(path : String,
                                     config : ConventionConfig,
                                     package_annotations : Hash(ScopedNameKey, String),
                                     content : String,
                                     root : LibTreeSitter::TSNode?)
      package_name = Noir::TreeSitterJavaParameterExtractor.extract_package_name(content)
      classes_in(content, package_name).each do |klass|
        next if klass.abstract?

        package_annotations_for_class = package_annotations[{configured_base_for(path), klass.package_name}]? || ""
        namespaces = namespace_values(klass.annotations)
        namespaces = namespace_values(package_annotations_for_class) if namespaces.empty?
        namespaces = [convention_namespace(klass.package_name, config)] if namespaces.empty?

        class_actions = action_paths_from_annotations(klass.annotations)
        class_action_base = convention_action_name(klass.name, config)
        class_has_action_annotation = !class_actions.empty?
        methods = methods_in(klass.body, klass.body_offset, content)

        namespaces.each do |class_namespace|
          class_actions.each do |action_path|
            resolved = action_path.empty? ? join_paths(class_namespace, class_action_base) : resolve_action_path(action_path, class_namespace)
            # A class-level @Action defaults to the `execute` handler.
            add_route(resolved, "ANY", path, klass.line, callees: callees_for(root, content, path, klass.name, "execute"))
          end

          methods.each do |method|
            action_paths = action_paths_from_annotations(method.annotations)
            next if action_paths.empty?

            action_paths.each do |action_path|
              resolved = action_path.empty? ? join_paths(class_namespace, class_action_base) : resolve_action_path(action_path, class_namespace)
              add_route(resolved, "ANY", path, method.line, callees: callees_for(root, content, path, klass.name, method.name))
            end
          end

          next if class_has_action_annotation || methods.any? { |method| !action_paths_from_annotations(method.annotations).empty? }
          next unless convention_action_class?(klass, config, package_annotations_for_class)

          base_path = join_paths(class_namespace, class_action_base)
          if rest_controller?(klass, config)
            add_rest_routes(path, base_path, methods, root, content, klass.name)
          else
            # A convention action without an explicit method defaults to `execute`.
            add_route(base_path, "ANY", path, klass.line, callees: callees_for(root, content, path, klass.name, "execute"))
          end
        end
      end
    end

    # 1-hop callees out of the action handler method body, mirroring the
    # Spring analyzer. Returns an empty list unless callee/ai-context
    # enrichment was requested (`root` is nil on a default scan). The
    # tree-sitter root is shared across every route in the file.
    private def callees_for(root : LibTreeSitter::TSNode?,
                            content : String,
                            path : String,
                            class_name : String,
                            method_name : String) : Array(Callee)
      callees = [] of Callee
      return callees if root.nil? || class_name.empty? || method_name.empty?

      Noir::JavaCalleeExtractor.callees_in_method(root, content, path, class_name, method_name).each do |entry|
        name, callee_path, callee_line = entry
        callees << Callee.new(name, path: callee_path, line: callee_line)
      end
      callees
    rescue e : Exception
      @logger.debug "Failed to extract Struts callees for #{class_name}##{method_name}: #{e.message}"
      [] of Callee
    end

    private def struts_java_source?(content : String, config : ConventionConfig) : Bool
      content.includes?("org.apache.struts2") ||
        content.includes?("com.opensymphony.xwork2") ||
        content.includes?("@Action") ||
        content.includes?("@Namespace") ||
        config.rest_enabled?
    end

    private def classes_in(content : String, package_name : String) : Array(JavaClass)
      classes = [] of JavaClass
      scanner = /(?:^|\n)\s*((?:public\s+|protected\s+|private\s+|abstract\s+|final\s+|static\s+)*)class\s+([A-Za-z_][A-Za-z0-9_]*)([^{]*)\{/m
      content.scan(scanner) do |match|
        modifiers = match[1]
        class_name = match[2]
        start_offset = match.begin(0)
        open_brace = match.end(0) - 1
        close_brace = matching_brace(content, open_brace)
        next unless close_brace

        annotations = annotations_before(content, start_offset)
        header = match[3]
        body = content[(open_brace + 1)...close_brace]
        classes << JavaClass.new(
          class_name,
          package_name,
          annotations,
          header,
          body,
          open_brace + 1,
          line_number_for(content, start_offset),
          modifiers.includes?("abstract")
        )
      end
      classes
    end

    private def methods_in(body : String, body_offset : Int32, full_content : String) : Array(JavaMethod)
      methods = [] of JavaMethod
      scanner = /(?:^|\n)\s*(?:public|protected|private)?\s*(?:static\s+)?(?:final\s+)?[\w<>\[\].?,\s]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^;{}]*\)\s*(?:throws\s+[^{]+)?\{/m
      body.scan(scanner) do |match|
        method_name = match[1]
        start_offset = body_offset + match.begin(0)
        annotations = annotations_before(full_content, start_offset)
        methods << JavaMethod.new(method_name, annotations, line_number_for(full_content, start_offset))
      end
      methods
    end

    private def annotations_before(content : String, offset : Int32) : String
      cursor = offset - 1
      while cursor >= 0 && content[cursor].ascii_whitespace?
        cursor -= 1
      end
      end_pos = cursor + 1

      loop do
        while cursor >= 0 && content[cursor].ascii_whitespace?
          cursor -= 1
        end
        break if cursor < 0

        if content[cursor] == ')'
          open_paren = matching_open_paren(content, cursor)
          break unless open_paren
          at_pos = annotation_start_before(content, open_paren)
          break unless at_pos
          cursor = at_pos - 1
        else
          line_start = content.rindex('\n', cursor) || -1
          line = content[(line_start + 1)..cursor].strip
          break unless line.matches?(/^@[A-Za-z_][A-Za-z0-9_.]*$/)
          cursor = line_start
        end
      end

      start_pos = cursor + 1
      return "" if start_pos >= end_pos
      content[start_pos...end_pos]
    end

    private def action_paths_from_annotations(annotations : String) : Array(String)
      paths = [] of String
      each_annotation_args(annotations, "Action") do |args|
        value = string_annotation_value(args, "value")
        paths << (value || "")
      end
      paths.uniq
    end

    private def annotation_value(annotations : String, name : String) : String?
      each_annotation_args(annotations, name) do |args|
        return string_annotation_value(args, "value")
      end
      nil
    end

    private def namespace_values(annotations : String) : Array(String)
      namespaces = [] of String
      each_annotation_args(annotations, "Namespace") do |args|
        if value = string_annotation_value(args, "value")
          namespaces << normalize_namespace(value)
        end
      end
      namespaces.uniq
    end

    private def each_annotation_args(text : String, name : String, &)
      offset = 0
      needle = "@#{name}"
      while index = text.index(needle, offset)
        after_name = index + needle.size
        if after_name < text.size && identifier_char?(text[after_name])
          offset = after_name
        else
          cursor = after_name
          while cursor < text.size && text[cursor].ascii_whitespace?
            cursor += 1
          end
          if cursor < text.size && text[cursor] == '('
            close = matching_close_paren(text, cursor)
            if close
              yield text[(cursor + 1)...close]
              offset = close + 1
            else
              offset = cursor + 1
            end
          else
            yield ""
            offset = cursor
          end
        end
      end
    end

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). Every caller probes the `value` key, so
    # precompile its matcher once at load time.
    VALUE_KEY_PATTERN = /(?:^|[,({]\s*)value\s*=\s*"((?:\\.|[^"\\])*)"/m

    private def string_annotation_value(args : String, key : String) : String?
      stripped = args.strip
      if stripped.starts_with?("\"")
        return unescape_java_string(stripped)
      end

      key_regex = key == "value" ? VALUE_KEY_PATTERN : /(?:^|[,({]\s*)#{Regex.escape(key)}\s*=\s*"((?:\\.|[^"\\])*)"/m
      if match = stripped.match(key_regex)
        return unescape_java_string("\"#{match[1]}\"")
      end

      nil
    end

    private def unescape_java_string(raw : String) : String
      content = raw.strip
      content = content[1..-2] if content.size >= 2 && content.starts_with?('"') && content.ends_with?('"')
      content.gsub(/\\(["\\])/, "\\1")
    end

    private def convention_action_class?(klass : JavaClass, config : ConventionConfig, package_annotations : String) : Bool
      suffix_match = config.action_suffixes.any? { |suffix| klass.name.ends_with?(suffix) }
      action_type = klass.header.includes?("ActionSupport") || klass.header.includes?("Action")
      return false unless suffix_match || action_type
      return true if annotation_value(klass.annotations, "Namespace")
      return true unless namespace_values(package_annotations).empty?
      return true if config.action_packages.any? { |pkg| klass.package_name == pkg || klass.package_name.starts_with?("#{pkg}.") }

      parts = klass.package_name.split(".")
      parts.any? { |part| config.locators.includes?(part) }
    end

    private def rest_controller?(klass : JavaClass, config : ConventionConfig) : Bool
      klass.name.ends_with?("Controller") && (config.rest_enabled? || config.action_suffixes.includes?("Controller"))
    end

    private def add_rest_routes(path : String,
                                base_path : String,
                                methods : Array(JavaMethod),
                                root : LibTreeSitter::TSNode?,
                                content : String,
                                class_name : String)
      methods.each do |method|
        route = REST_METHODS[method.name]?
        next unless route

        verb, suffix = route
        params = suffix.includes?(":id") ? [Param.new("id", "", "path")] : [] of Param
        add_route(join_paths(base_path, suffix), verb, path, method.line, params,
          callees: callees_for(root, content, path, class_name, method.name))
      end
    end

    private def convention_namespace(package_name : String, config : ConventionConfig) : String
      return "" if package_name.empty?

      config.action_packages.each do |pkg|
        next unless package_name == pkg || package_name.starts_with?("#{pkg}.")
        suffix = package_name[pkg.size..]? || ""
        return package_to_namespace(suffix.lstrip('.'))
      end

      parts = package_name.split(".")
      locator_index = parts.index { |part| config.locators.includes?(part) }
      return "" unless locator_index
      package_to_namespace(parts[(locator_index + 1)..].join("."))
    end

    private def package_to_namespace(package_suffix : String) : String
      return "" if package_suffix.empty?
      "/#{package_suffix.split(".").map { |part| camel_to_kebab(part) }.join("/")}"
    end

    private def convention_action_name(class_name : String, config : ConventionConfig) : String
      suffix = config.action_suffixes.find { |candidate| class_name.ends_with?(candidate) }
      base = suffix ? class_name[0...(class_name.size - suffix.size)] : class_name
      base = class_name if base.empty?
      camel_to_kebab(base)
    end

    private def camel_to_kebab(value : String) : String
      value
        .gsub(/([a-z0-9])([A-Z])/, "\\1-\\2")
        .gsub(/([A-Z]+)([A-Z][a-z])/, "\\1-\\2")
        .tr("_", "-")
        .downcase
    end

    private def resolve_action_path(action_path : String, namespace : String) : String
      return join_paths(namespace, action_path) unless action_path.starts_with?("/")
      normalize_path(action_path)
    end

    private def normalize_action_pattern(action_name : String) : String
      normalized = action_name.strip
      normalized = normalized[0...-7] if normalized.ends_with?(".action")
      normalized = normalized.gsub(/\{([A-Za-z_][A-Za-z0-9_]*)\}/, ":\\1")
      normalized.empty? ? "" : normalized
    end

    private def add_route(path : String, method : String, file_path : String, line : Int32?,
                          params = [] of Param, callees : Array(Callee) = [] of Callee)
      normalized = normalize_path(path)
      route_params = params.dup
      wildcard_count = normalized.count('*')
      wildcard_count.times do |index|
        name = index == 0 ? "wildcard" : "wildcard#{index + 1}"
        route_params << Param.new(name, "", "path")
      end

      normalized.scan(/:([A-Za-z_][A-Za-z0-9_]*)/) do |match|
        name = match[1]
        route_params << Param.new(name, "", "path") unless route_params.any? { |param| param.name == name && param.param_type == "path" }
      end

      key = "#{method} #{normalized}"
      return if @result.any? { |endpoint| "#{endpoint.method} #{endpoint.url}" == key }

      endpoint = Endpoint.new(normalized, method, route_params, Details.new(PathInfo.new(file_path, line)))
      callees.each { |callee| endpoint.push_callee(callee) }
      @result << endpoint
    end

    private def normalize_namespace(namespace : String) : String
      cleaned = namespace.strip
      return "" if cleaned.empty? || cleaned == "/"
      normalize_path(cleaned)
    end

    private def normalize_path(path : String) : String
      cleaned = path.strip
      return "/" if cleaned.empty? || cleaned == "/"
      cleaned = "/#{cleaned}" unless cleaned.starts_with?("/")
      cleaned.gsub(%r{/+}, "/").rstrip('/')
    end

    private def join_paths(prefix : String, suffix : String) : String
      return normalize_path(prefix) if suffix.empty? || suffix == "/"
      return normalize_path(suffix) if prefix.empty? || prefix == "/"
      normalize_path("#{prefix.rstrip('/')}/#{suffix.lstrip('/')}")
    end

    private def split_csv(value : String) : Array(String)
      value.split(",").map(&.strip).reject(&.empty?)
    end

    private def xml_line_for(content : String, action_name : String, from_offset : Int32 = 0) : Int32?
      pattern = /<action\b[^>]*\bname\s*=\s*["']#{Regex.escape(action_name)}["']/
      if index = content.index(pattern, from_offset)
        return line_number_for(content, index)
      end
      # Fall back to a document-wide search when the package anchor
      # didn't land before the declaration (e.g. attributes reordered).
      if from_offset > 0 && (index = content.index(pattern))
        return line_number_for(content, index)
      end
      nil
    end

    # Byte offset of a package's opening `<package … name="…">` tag, used
    # to scope action-line lookups to the declaring package.
    private def package_start_offset(content : String, package_name : String) : Int32
      if index = content.index(/<package\b[^>]*\bname\s*=\s*["']#{Regex.escape(package_name)}["']/)
        return index
      end
      0
    end

    private def line_number_for(content : String, offset : Int32) : Int32
      # Callers pass CHAR offsets (match.begin / String#index); char-slice so
      # multi-byte chars before `offset` don't under-count newlines.
      content[0, offset].count('\n') + 1
    end

    private def matching_brace(content : String, open_index : Int32) : Int32?
      depth = 0
      in_string : Char? = nil
      escaped = false

      index = open_index
      while index < content.size
        char = content[index]
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == in_string
            in_string = nil
          end
        elsif char == '"' || char == '\''
          in_string = char
        elsif char == '{'
          depth += 1
        elsif char == '}'
          depth -= 1
          return index if depth == 0
        end
        index += 1
      end
      nil
    end

    private def matching_open_paren(content : String, close_index : Int32) : Int32?
      depth = 0
      index = close_index
      while index >= 0
        case content[index]
        when ')'
          depth += 1
        when '('
          depth -= 1
          return index if depth == 0
        end
        index -= 1
      end
      nil
    end

    private def matching_close_paren(content : String, open_index : Int32) : Int32?
      depth = 0
      in_string : Char? = nil
      escaped = false

      index = open_index
      while index < content.size
        char = content[index]
        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == in_string
            in_string = nil
          end
        elsif char == '"' || char == '\''
          in_string = char
        elsif char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
          return index if depth == 0
        end
        index += 1
      end
      nil
    end

    private def annotation_start_before(content : String, open_paren : Int32) : Int32?
      index = open_paren - 1
      while index >= 0 && content[index].ascii_whitespace?
        index -= 1
      end
      while index >= 0 && (identifier_char?(content[index]) || content[index] == '.')
        index -= 1
      end
      return unless index >= 0 && content[index] == '@'
      index
    end

    private def identifier_char?(char : Char) : Bool
      char.ascii_letter? || char.ascii_number? || char == '_'
    end

    private def xml_attr(node : XML::Node, name : String) : String
      node[name]?.try(&.strip) || ""
    end

    private def find_xml_child(node : XML::Node, local_name : String) : XML::Node?
      node.children.each do |child|
        return child if child.element? && child.name == local_name
      end
      nil
    end

    private def each_xml_child(node : XML::Node, local_name : String, &)
      node.children.each do |child|
        yield child if child.element? && child.name == local_name
      end
    end
  end
end
