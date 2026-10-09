require "../../models/analyzer"
require "../../miniparsers/jaxrs_extractor_ts"
require "../../miniparsers/kotlin_route_extractor_ts"
require "../../miniparsers/import_graph"
require "../../utils/c_comments"
require "yaml"
require "../../utils/path_scope"

# Shared helpers for the Java analyzers. They each extend `Analyzer`
# directly rather than a language-specific engine (historically the
# Java set was the first family to land and never got an intermediate
# class), so the helpers live as class methods on the JavaEngine
# module and the callers import it explicitly. Mirrors the pattern
# `Analyzer::Kotlin::KotlinEngine` follows. Helpers that need the
# analyzer instance (`read_file_content`) are private instance methods
# instead, picked up with `include JavaEngine` — the JAX-RS family and
# the Spring/Micronaut config readers, Kotlin Spring included.
module Analyzer::Java
  module JavaEngine
    # Maven/Gradle pin test sources to `src/test/<lang>/` — `java`,
    # `kotlin`, `scala`, `groovy` all share the layout. Real route
    # handlers never live there, but Quarkus, Micronaut, Spring,
    # Javalin, JAX-RS and friends routinely declare inline
    # controllers under `src/test/java/...` to exercise the
    # framework. The path layout is part of the build tool's
    # contract so the prefix check is unambiguous.
    #
    # Also covers Maven's archetype source-roots
    # (`src/it/`, integration-test convention used by some Quarkus
    # extensions and Apache projects) which sit alongside `src/test/`.
    #
    # Takes the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one. The layout is a contract between the build
    # tool and the *project*, so matching the absolute path let a
    # directory above the scan base decide the answer — a CI job that
    # checks out under a `src/test/` step directory silently lost 375 of
    # the fixture tree's 396 endpoints.
    def self.test_path?(relative_path : String) : Bool
      return true if relative_path.includes?("/src/test/")
      return true if relative_path.includes?("/src/it/")
      false
    end

    # Index of the delimiter closing the `open_char` at `open_idx`, or nil when
    # the source runs out first. String and char literals are skipped, so a
    # `)`/`}` inside `"…"` or `'…'` cannot close the block early.
    #
    # Scan by CHARACTER (not byte): `open_idx` is a char index from
    # `String#index` and callers char-slice with — or range-compare — the
    # returned index. A byte scan corrupts both on multi-byte UTF-8.
    # ASCII-identical to the previous byte loop. The walk starts at
    # `open_idx` rather than skipping up to it from the file head, which
    # made one call per route quadratic over a large file.
    def self.find_matching_delimiter(code : String,
                                     open_idx : Int32,
                                     open_char : Char,
                                     close_char : Char) : Int32?
      depth = 1
      in_string = false
      quote = '\0'
      escape = false

      each_char_after(code, open_idx) do |ch, i|
        if in_string
          if escape
            escape = false
          elsif ch == '\\'
            escape = true
          elsif ch == quote
            in_string = false
          end
        else
          if ch == '"' || ch == '\''
            in_string = true
            quote = ch
          elsif ch == open_char
            depth += 1
          elsif ch == close_char
            depth -= 1
          end
        end
        return i if depth == 0
      end

      nil
    end

    # Yields each char after char index `index` with its char index.
    def self.each_char_after(code : String, index : Int32, &)
      return unless byte_index = code.char_index_to_byte_index(index + 1)
      reader = Char::Reader.new(code, byte_index)
      i = index + 1
      while reader.pos < code.bytesize
        yield reader.current_char, i
        reader.next_char
        i += 1
      end
    end

    # Replaces `//` line comments and `/* */` block comments with spaces
    # (newlines preserved) so a commented-out annotation or call is never
    # mistaken for a live one, while keeping every real line number stable
    # for PathInfo reporting. String and char literals are tracked so `//`
    # or `/*` inside a literal (e.g. a URL default value `"http://x//y"`) is
    # never treated as a comment opener.
    def self.strip_comments(text : String) : String
      Noir::CComments.strip(text, leak_unterminated_tail: true)
    end

    # Module root of a Maven/Gradle source file: everything before
    # `/src/main/java/` (or `/src/main/kotlin/`), or the file's own directory
    # outside that layout.
    def self.project_root_for(path : String) : String
      marker_root(path, {"/src/main/java/", "/src/main/kotlin/"}) || File.dirname(path)
    end

    # `path` up to the first of `markers` (tried in order) it contains, or
    # nil when it contains none.
    def self.marker_root(path : String, markers : Enumerable(String)) : String?
      markers.each do |marker|
        if index = path.index(marker)
          return path[...index]
        end
      end
      nil
    end

    # `server.servlet.context-path` / `spring.webflux.base-path` of one
    # Spring module (Java and Kotlin analyzers alike).
    struct SpringPathConfig
      getter servlet_context_path : String
      getter webflux_base_path : String

      def initialize(@servlet_context_path = "", @webflux_base_path = "")
      end

      def web_base_path : String
        @webflux_base_path.empty? ? @servlet_context_path : @webflux_base_path
      end
    end

    # The instance helpers below are shared by the analyzers that
    # `include JavaEngine`. `application_base_path_for` calls the
    # includer's own `project_root_for`.

    # `route` is any JVM extractor's `Route` (JAX-RS, Micronaut): verb,
    # params, 0-based line, `{name, line}` callees and protocol. `file` is
    # where the route and its callees live.
    private def jvm_route_endpoint(route, url : String, file : String) : Endpoint
      endpoint = Endpoint.new(url, route.verb, route.params, Details.new(PathInfo.new(file, route.line + 1)))
      endpoint.protocol = route.protocol
      route.callees.each do |(name, line)|
        endpoint.push_callee(Callee.new(name, path: file, line: line))
      end
      endpoint
    end

    private def jvm_source?(path : String) : Bool
      path.ends_with?(".java") || path.ends_with?(".kt")
    end

    # Record a Kotlin `@ApplicationPath` under `{project root, package}`,
    # the key `application_base_path_for` reads.
    private def add_kotlin_application_path(path : String,
                                            content : String,
                                            base_paths : Hash(Tuple(String, String), String))
      Noir::TreeSitter.parse_kotlin(content) do |root|
        key = {project_root_for(path), Noir::TreeSitterKotlinParameterExtractor.extract_package_name_from(root, content)}
        next if base_paths.has_key?(key)
        if base_path = Noir::TreeSitterKotlinRouteExtractor.extract_jaxrs_application_path_from(root, content)
          base_paths[key] = base_path
        end
      end
    end

    private def application_base_path_for(path : String,
                                          package_name : String,
                                          base_paths : Hash(Tuple(String, String), String)) : String
      project_root = project_root_for(path)
      keys = base_paths.keys.select { |key| key[0] == project_root }
      keys.sort_by!(&.[1].size)
      keys.reverse_each do |key|
        base_package = key[1]
        next unless package_name == base_package || package_name.starts_with?("#{base_package}.")
        return base_paths[key]
      end
      ""
    end

    # Build the cross-file `@BeanParam` index for `path`. Same
    # traversal as the DTO index — current file + same-package
    # siblings + imports — but each file's `extract_bean_fields`
    # result is memoised in the analyzer's per-run cache.
    private def bean_index_for(path : String,
                               content : String,
                               package_name : String,
                               cache : Hash(String, Hash(String, Array(Param))),
                               imports : Array(Noir::ImportGraph::ImportRef)? = nil,
                               current_file_beans : Hash(String, Array(Param))? = nil) : Hash(String, Array(Param))
      result = Hash(String, Array(Param)).new
      resolved_imports = imports || Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, resolved_imports, "java") do |file|
        beans = cache[file] ||= begin
          if file == path && current_file_beans
            current_file_beans
          else
            body = file == path ? content : read_file_content(file)
            Noir::TreeSitterJaxRsExtractor.extract_bean_fields(body)
          end
        rescue IO::Error
          {} of String => Array(Param)
        end

        beans.each { |name, params| result[name] ||= params }
      end

      result
    end

    # Build the cross-file `@HttpMethod("VERB")` custom-annotation
    # index for `path`. Same traversal as `bean_index_for` — the
    # annotation type is typically declared in its own file, so this
    # needs the same current file + same-package siblings + imports
    # walk, gated on the file mentioning JAX-RS so unrelated `.java`
    # files aren't parsed for annotation declarations.
    private def custom_verb_index_for(path : String,
                                      content : String,
                                      package_name : String,
                                      cache : Hash(String, Hash(String, String)),
                                      imports : Array(Noir::ImportGraph::ImportRef)? = nil,
                                      current_file_verbs : Hash(String, String)? = nil) : Hash(String, String)
      result = Hash(String, String).new
      resolved_imports = imports || Noir::TreeSitterJavaParameterExtractor.extract_imports(content)

      Noir::ImportGraph.related_files(path, package_name, resolved_imports, "java") do |file|
        verbs = cache[file] ||= begin
          if file == path && current_file_verbs
            current_file_verbs
          else
            body = file == path ? content : read_file_content(file)
            if body.includes?("jakarta.ws.rs") || body.includes?("javax.ws.rs")
              Noir::TreeSitterJaxRsExtractor.extract_custom_verb_annotations(body)
            else
              Hash(String, String).new
            end
          end
        rescue IO::Error
          Hash(String, String).new
        end

        verbs.each { |name, verb| result[name] ||= verb }
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

      Noir::ImportGraph.related_files(path, package_name, resolved_imports, "java") do |file|
        body = cache[file] ||= begin
          file == path ? content : read_file_content(file)
        rescue IO::Error
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

    private def resource_dirs_for(project_root : String) : Array(String)
      [
        File.join(project_root, "src/main/resources"),
        File.join(project_root, "resources"),
        project_root,
      ].uniq
    end

    private def read_properties(path : String) : Hash(String, String)
      values = Hash(String, String).new
      read_file_content(path).each_line do |line|
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

    # Flattened `application.properties` / `.yml` / `.yaml` keys of one
    # Spring module (`spring.data.rest.base-path`, `vaadin.endpoint.prefix`, ...).
    private def spring_config_values_for(project_root : String) : Hash(String, String)
      values = Hash(String, String).new

      resource_dirs_for(project_root).each do |dir|
        properties_path = File.join(dir, "application.properties")
        values.merge!(read_properties(properties_path)) if File.exists?(properties_path)

        yml_path = File.join(dir, "application.yml")
        yaml_path = File.join(dir, "application.yaml")
        merge_yaml_properties(values, yml_path) if File.exists?(yml_path)
        merge_yaml_properties(values, yaml_path) if File.exists?(yaml_path)
      end

      values
    end

    private def merge_yaml_properties(values : Hash(String, String), path : String)
      document = YAML.parse(read_file_content(path))
      flatten_yaml_properties("", document, values)
    rescue
      # Ignore unreadable or malformed YAML.
    end

    private def flatten_yaml_properties(prefix : String, node : YAML::Any, target : Hash(String, String))
      if hash = yaml_hash(node)
        hash.each do |key, value|
          key_string = key.to_s
          child_prefix = prefix.empty? ? key_string : "#{prefix}.#{key_string}"
          flatten_yaml_properties(child_prefix, value, target)
        end
      elsif scalar = yaml_scalar(node)
        target[prefix] = scalar unless prefix.empty?
      end
    end

    private def yaml_hash(node : YAML::Any) : Hash(YAML::Any, YAML::Any)?
      node.as_h
    rescue
      nil
    end

    private def yaml_scalar(node : YAML::Any) : String?
      node.as_s
    rescue
      if int = node.as_i64?
        int.to_s
      end
    end

    # The Maven/Gradle module root: everything above the source root that
    # holds this file.
    #
    # The marker is searched inside the scan-base-relative path, never the
    # absolute one. `String#index` returns the FIRST occurrence, so on an
    # absolute path a `src/` directory anywhere above the scan base won
    # outright and the module root resolved to a directory outside the
    # scan — `application.properties` was then never found and every
    # `server.servlet.context-path` prefix silently vanished.
    # Default for includers; JAX-RS, Quarkus and Helidon MP override it,
    # and `JavaEngine.project_root_for` above is the absolute-path variant
    # Micronaut and Dropwizard call.
    private def project_root_for(path : String) : String
      base = configured_base_for(path)
      relative = Noir::PathScope.base_relative(path, base)

      ["/src/main/java/", "/src/"].each do |marker|
        if index = relative.index(marker)
          return base.rstrip('/') + relative[...index]
        end
      end

      base
    end

    private def normalize_optional_path(path : String?) : String
      return "" unless path

      trimmed = path.strip
      return "" if trimmed.empty? || trimmed == "/"
      trimmed.starts_with?("/") ? trimmed : "/#{trimmed}"
    end

    private def add_interface_routes(target : Array(T),
                                     seen : Set(String),
                                     routes : Array(T)?) forall T
      return unless routes

      routes.each do |entry|
        route = entry.route
        key = "#{entry.path}:#{route.class_name}:#{route.method_name}:#{route.verb}:#{route.path}"
        next if seen.includes?(key)
        seen << key
        target << entry
      end
    end
  end
end
