require "../../models/analyzer"
require "../../miniparsers/jaxrs_extractor_ts"
require "../../miniparsers/kotlin_route_extractor_ts"
require "../../miniparsers/import_graph"
require "../../utils/c_comments"
require "yaml"
require "../../utils/path_scope"
require "../../utils/url_path"

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
    # extensions and Apache projects) which sit alongside `src/test/`,
    # and Gradle's extra test source sets (`testFixtures`, `jmh`,
    # `integrationTest`, `functionalTest`, and `integration` from the
    # com.coditory.integration-test plugin).
    TEST_SOURCE_SET_RE = Regex.union(
      "/src/test/",
      "/src/it/",
      "/src/testFixtures/",
      "/src/jmh/",
      "/src/integrationTest/",
      # Not when a `src/main/` follows: then `integration` is a module name.
      %r{/src/integration/(?!(?:.*/)?src/main/)},
      "/src/functionalTest/",
    )

    # Takes the scan-base-relative path (`Analyzer#base_relative_path`),
    # never the absolute one. The layout is a contract between the build
    # tool and the *project*, so matching the absolute path let a
    # directory above the scan base decide the answer — a CI job that
    # checks out under a `src/test/` step directory silently lost 375 of
    # the fixture tree's 396 endpoints.
    #
    # `FooTest.java` / `FooTests.java` (and `.kt`, which Javalin, Micronaut,
    # Quarkus and JAX-RS read through the same predicate) are JUnit classes
    # even when they sit in `src/main/java` of a published test kit (the
    # Micronaut TCK declares its `@Requires(property = "spec.name")`
    # controllers there). The suffix check is case-sensitive, so
    # `Latest.java` is not a hit, and it needs a name before the suffix: a
    # class literally called `Test` or `Tests` is a tutorial's servlet, not
    # a test.
    TEST_CLASS_FILE_RE = /.(?:Test|Tests)\.(?:java|kt)\z/

    def self.test_path?(relative_path : String) : Bool
      return true if relative_path.matches?(TEST_SOURCE_SET_RE)
      File.basename(relative_path).matches?(TEST_CLASS_FILE_RE)
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

    # What a Java file sees when it names a type: its package, its imports
    # and the type names it declares itself (nested ones included).
    record NameScope, package_name : String, imports : Array(Noir::ImportGraph::ImportRef), declared : Set(String)

    DECLARATION_NODE_TYPES = Set{"class_declaration", "interface_declaration", "enum_declaration",
                                 "record_declaration", "annotation_type_declaration"}

    def self.name_scope(source : String) : NameScope
      scope = NameScope.new("", Array(Noir::ImportGraph::ImportRef).new, Set(String).new)
      Noir::TreeSitter.parse_java(source) do |root|
        declared = Set(String).new
        collect_declared_types(root, source, declared)
        scope = NameScope.new(Noir::TreeSitterJavaParameterExtractor.extract_package_name_from(root, source),
          Noir::TreeSitterJavaParameterExtractor.extract_imports_from(root, source), declared)
      end
      scope
    end

    private def self.collect_declared_types(node : LibTreeSitter::TSNode, source : String, names : Set(String))
      if DECLARATION_NODE_TYPES.includes?(Noir::TreeSitter.node_type(node))
        Noir::TreeSitter.field(node, "name").try { |name| names << Noir::TreeSitter.node_text(name, source) }
      end
      Noir::TreeSitter.each_named_child(node) { |child| collect_declared_types(child, source, names) }
    end

    # True when the type name `written` in `file` (simple or qualified,
    # generic arguments ignored) is `fqn`, resolved the way javac does: a
    # qualified name stands for itself; a simple one goes to a single-type
    # import, then a type the file declares, then its own package, then an
    # on-demand import. `unresolved` answers when none of those names it (a
    # type from an implicit or unscanned package).
    def self.type_resolves_to?(written : String, fqn : String, file : String, scope : NameScope,
                               unresolved : Bool = false) : Bool
      name = written.split('<', 2).first.strip
      return name == fqn if name.includes?('.')

      fqn_package, _, simple = fqn.rpartition('.')
      return false unless name == simple
      if single = scope.imports.find { |imp| !imp.wildcard? && imp.path.rpartition('.').last == name }
        return single.path == fqn
      end
      return false if scope.declared.includes?(name)

      dir = File.dirname(file)
      if CodeLocator.instance.files_by_basename("#{name}.java").any? { |path| File.dirname(path) == dir }
        return scope.package_name == fqn_package
      end
      return true if scope.imports.any? { |imp| imp.wildcard? && imp.path == fqn_package }
      unresolved
    end

    # The project file declaring the JVM type `type` as `source` names it:
    # by its single-type import, else in `source`'s own package.
    def self.java_type_file(type : String, source : String) : String?
      if type.includes?('.')
        fqn = type
        type = type.split('.').last
      end
      fqn ||=
        if import = source.match(/^\s*import\s+([\w$.]+)\.#{Regex.escape(type)}\s*;?\s*$/m)
          "#{import[1]}.#{type}"
        elsif package = source.match(/^\s*package\s+([\w$.]+)\s*;?\s*$/m)
          "#{package[1]}.#{type}"
        else
          type
        end
      stem = "/#{fqn.gsub('.', '/')}"
      {".java", ".kt"}.each do |ext|
        if file = CodeLocator.instance.files_by_basename("#{type}#{ext}").find(&.ends_with?("#{stem}#{ext}"))
          return file
        end
      end
      nil
    end

    # Module root of a Maven/Gradle source file: everything before
    # `/src/main/java/` (or `/src/main/kotlin/`) below `base`, or the file's
    # own directory outside that layout.
    def self.project_root_for(path : String, base : String) : String
      Noir::PathScope.marker_root(path, base, {"/src/main/java/", "/src/main/kotlin/"}) || File.dirname(path)
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
      endpoint.handler = jvm_route_handler(route, file)
      route.callees.each do |(name, line)|
        endpoint.push_callee(Callee.new(name, path: file, line: line))
      end
      endpoint
    end

    # The method an annotation-declared route decorates, as
    # `Class.method` at its signature line (1-based). nil for class-level
    # routes (no method) and for routes whose extractor has no
    # `signature_line`.
    private def jvm_route_handler(route, file : String) : Handler?
      return if route.class_name.empty? || route.method_name.empty?
      signature_line = route.signature_line || return
      Handler.new("#{route.class_name}.#{route.method_name}", file, signature_line + 1)
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
        # An empty package is a root-wide mount (a servlet mapping that
        # names no Application or packages); longer packages win first.
        next unless base_package.empty? || package_name == base_package || package_name.starts_with?("#{base_package}.")
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
      elsif items = node.as_a?
        # A YAML list binds like Spring's comma-separated form
        # (`static-locations`, `exposure.include`).
        scalars = items.compact_map { |item| yaml_scalar(item) }
        target[prefix] = scalars.join(',') unless prefix.empty? || scalars.empty?
      end
    end

    private def yaml_hash(node : YAML::Any) : Hash(YAML::Any, YAML::Any)?
      node.as_h
    rescue
      nil
    end

    private def yaml_scalar(node : YAML::Any) : String?
      case raw = node.raw
      when String, Int64, Float64, Bool then raw.to_s
      end
    end

    # Spring Boot's four classpath defaults for `spring.web.resources.static-locations`.
    SPRING_DEFAULT_STATIC_LOCATIONS = ["classpath:/META-INF/resources/", "classpath:/resources/", "classpath:/static/", "classpath:/public/"]

    # Actuator endpoints every Boot app has once they are exposed; the rest
    # (prometheus, flyway, ...) need their own dependency, so they are
    # emitted only when `exposure.include` names them.
    SPRING_ACTUATOR_CORE = %w[health info beans caches conditions configprops env loggers heapdump threaddump metrics scheduledtasks mappings]

    SPRING_ACTUATOR_DEP_RE   = /spring[-.]boot[-.]starter[-.]actuator\b/
    SPRING_SPRINGDOC_DEP_RE  = /springdoc[-.]openapi/
    SPRING_SWAGGER_UI_DEP_RE = /springdoc[-.]openapi[\w.-]*?[-.]ui\b/
    # Comments and Maven `<dependencyManagement>` (which only pins versions)
    # are not dependencies; masked to spaces so offsets keep their lines.
    SPRING_BUILD_NOISE_RE = /<!--.*?-->|<dependencyManagement>.*?<\/dependencyManagement>|\/\*.*?\*\/|\/\/[^\n]*/m

    FRAMEWORK_PROVIDED_TAG = Tag.new("framework-provided", "Served by Spring Boot / Spring Security itself, not by an application controller", "spring_analyzer")
    # The login / logout / OAuth2 routes: a filter of the chain answers them,
    # and every one of those filters runs before the `AuthorizationFilter`,
    # so no `authorizeHttpRequests` rule (`anyRequest().authenticated()`)
    # ever sees the request.
    SECURITY_FILTER_TAG = Tag.new("framework-provided", "Served by a Spring Security filter, which answers it before any authorization rule applies", "spring_analyzer")

    # Routes the Spring Boot runtime serves for a module with no controller
    # behind them: every file under the static-resource locations, the
    # exposed Actuator endpoints and the springdoc documents. `values` is
    # the module's `spring_config_values_for`; actuator and springdoc also
    # need their dependency in a build file, so config alone emits nothing.
    private def spring_provided_endpoints(project_root : String, values : Hash(String, String), base_path : String) : Array(Endpoint)
      endpoints = spring_static_endpoints(project_root, values, base_path)

      if evidence = spring_build_dependency(project_root, SPRING_ACTUATOR_DEP_RE)
        # A separate management port drops the servlet context path.
        prefix = values.has_key?("management.server.port") ? normalize_optional_path(values["management.server.base-path"]? || values["management.server.servlet.context-path"]?) : base_path
        actuator_base = Noir::URLPath.join_rooted(prefix, values["management.endpoints.web.base-path"]? || "/actuator")
        listed = (values["management.endpoints.web.exposure.include"]? || "health").split(',').map(&.strip)
        excluded = (values["management.endpoints.web.exposure.exclude"]? || "").split(',').map(&.strip)
        ids = listed.includes?("*") ? (SPRING_ACTUATOR_CORE + listed).uniq : listed
        ids = ids.reject { |id| id.empty? || id == "*" || excluded.includes?(id) || !spring_actuator_enabled?(values, id) }
        unless ids.empty?
          endpoints << framework_endpoint(actuator_base, "GET", evidence)
          ids.each do |id|
            url = Noir::URLPath.join_rooted(actuator_base, values["management.endpoints.web.path-mapping.#{id}"]? || id)
            endpoints << framework_endpoint(url, id == "shutdown" ? "POST" : "GET", evidence)
          end
        end
      end

      if evidence = spring_build_dependency(project_root, SPRING_SPRINGDOC_DEP_RE)
        unless values["springdoc.api-docs.enabled"]? == "false"
          endpoints << framework_endpoint(Noir::URLPath.join_rooted(base_path, values["springdoc.api-docs.path"]? || "/v3/api-docs"), "GET", evidence)
        end
        if (ui = spring_build_dependency(project_root, SPRING_SWAGGER_UI_DEP_RE)) && values["springdoc.swagger-ui.enabled"]? != "false"
          endpoints << framework_endpoint(Noir::URLPath.join_rooted(base_path, values["springdoc.swagger-ui.path"]? || "/swagger-ui.html"), "GET", ui)
        end
      end

      endpoints
    end

    private def spring_actuator_enabled?(values : Hash(String, String), id : String) : Bool
      enabled = values["management.endpoint.#{id}.enabled"]? || values["management.endpoints.enabled-by-default"]?
      access = values["management.endpoint.#{id}.access"]? || values["management.endpoints.access.default"]?
      # `shutdown` is the one endpoint Boot ships disabled.
      return false if id == "shutdown" && enabled != "true" && access.nil?
      enabled != "false" && access != "none"
    end

    private def framework_endpoint(url : String, verb : String, evidence : PathInfo, params = [] of Param, tag = FRAMEWORK_PROVIDED_TAG) : Endpoint
      endpoint = Endpoint.new(url, verb, params, Details.new(evidence))
      endpoint.add_tag(tag)
      endpoint
    end

    # Where `pattern` (a dependency coordinate) is declared in the module's
    # `pom.xml` / `build.gradle(.kts)`, or in a parent module's up to the
    # scan base (Maven parents and Gradle `subprojects {}` hand theirs down).
    #
    # ponytail: Gradle convention plugins (`buildSrc`) are not followed.
    private def spring_build_dependency(project_root : String, pattern : Regex) : PathInfo?
      dir = project_root
      while within_scan_base?(dir)
        {"pom.xml", "build.gradle", "build.gradle.kts"}.each do |name|
          file = File.join(dir, name)
          next unless File.exists?(file)
          content = read_file_content(file)
          next unless content_matches?(content, pattern)
          masked = content.gsub(SPRING_BUILD_NOISE_RE, &.gsub(/[^\n]/, ' '))
          if match = pattern.match(masked)
            return PathInfo.new(file, line_number_for_index(masked, match.begin(0)))
          end
        end
        parent = File.dirname(dir)
        break if parent == dir
        dir = parent
      end
      nil
    end

    # Files that configure an `HttpSecurity` / `ServerHttpSecurity` chain.
    SPRING_SECURITY_FILE_RE = Regex.union("HttpSecurity", "SecurityFilterChain", "SecurityWebFilterChain", "WebSecurityConfigurerAdapter")
    # `.formLogin(` / `.logout(` (Java, Kotlin `http.` calls) or the Kotlin
    # DSL's `formLogin {` — a bare `logout(` is any app's own method, and a
    # dotted one counts only on an `HttpSecurity` chain (`spring_security_receiver?`).
    SPRING_SECURITY_DSL_RE    = /(?:\.\s*(formLogin|logout|oauth2Login)\s*\(|\b(formLogin|logout|oauth2Login)\s*\{)/
    SPRING_SECURITY_SETTER_RE = /\b(loginPage|loginProcessingUrl|usernameParameter|passwordParameter|logoutUrl|baseUri)\s*(?:\(\s*|=\s*)/
    SPRING_SECURITY_VAR_RE    = /\b(?:Server)?HttpSecurity\s+([a-z_$][\w$]*)|\b([a-z_$][\w$]*)\s*:\s*(?:Server)?HttpSecurity\b/
    # Where one security chain's source starts (its bean method).
    SPRING_CHAIN_START_RE = /\bSecurity(?:Web)?FilterChain\b|configure\s*\(\s*(?:final\s+)?(?:Server)?HttpSecurity/
    # `securityMatcher(s)(...)` / Spring 5 `http.antMatcher(...)` /
    # `http.requestMatcher(...)`: the requests a chain (and so its filters) sees.
    SPRING_CHAIN_SCOPE_RE = /\bsecurityMatchers?\s*\(|(?<!AntPathRequestMatcher)\.\s*(?:antMatcher|requestMatcher)\s*\(/
    # `logoutRequestMatcher(new AntPathRequestMatcher("/x"[, "GET"]))`.
    SPRING_LOGOUT_MATCHER_RE = /\A\s*new\s+AntPathRequestMatcher\s*\(\s*"([^"\\]*)"\s*(?:,\s*(?:"([A-Z]+)"|HttpMethod\.([A-Z]+)\.name\(\s*\)))?\s*\)\s*\)/
    JAVA_STRING_RE           = /"(?:[^"\\\n]|\\.)*"/

    # `.logoutSuccessHandler(handler)` / `(new Impl())`, Kotlin
    # `logoutSuccessHandler = handler`.
    SPRING_LOGOUT_SUCCESS_RE = /\blogoutSuccessHandler\s*(?:\(\s*|=\s*)(?:new\s+([A-Z][\w$.]*)\s*\(|([a-z_$][\w$]*)\s*(?:\)|$))/m

    # verb, path, form params, offset of the DSL call in `code`, the type
    # of the `LogoutSuccessHandler` a logout route ends in (written as
    # `new Impl()`) or the variable holding it, and whether the route is
    # inside its chain's `securityMatcher` (its filter answers it).
    alias SpringSecurityRoute = Tuple(String, String, Array(String), Int32, String?, Bool)

    # The login / logout / OAuth2 endpoints Spring Security's filters serve
    # for each `formLogin` / `logout` / `oauth2Login` of an `HttpSecurity`
    # chain, with the configured URLs and parameter names or Spring's
    # defaults. `code` is comment-stripped source. Values are string
    # literals or `static final String` / `const val` constants of the file;
    # a URL set any other way (a constant of another class, a request
    # matcher) is unknown, so that configurer yields no route rather than
    # the default one.
    def self.spring_security_routes(code : String) : Array(SpringSecurityRoute)
      routes = [] of SpringSecurityRoute
      masked = code.gsub(JAVA_STRING_RE) { |literal| "\"#{" " * (literal.size - 2)}\"" }
      return routes unless masked.matches?(SPRING_SECURITY_DSL_RE)
      chars = masked.chars
      receivers = Set(String).new
      masked.scan(SPRING_SECURITY_VAR_RE) { |match| receivers << (match[1]? || match[2]) }
      return routes if receivers.empty?

      masked.scan(SPRING_SECURITY_DSL_RE) do |match|
        dotted = !match[1]?.nil?
        kind = match[1]? || match[2]
        offset = match.begin(0)
        next unless spring_security_receiver?(chars, offset, dotted, receivers)
        from, to = spring_security_scope(masked, match.end(0) - 1)
        next if masked[from...to].matches?(/\bdisable\b/)
        scope = code[from...to]
        masked_scope = masked[from...to]
        values, unknown = spring_security_values(scope, masked_scope, code)
        scoped = spring_chain_patterns(code, masked, offset)
        served = ->(url : String) { scoped.nil? || scoped.any? { |pattern| ant_matches?(url, pattern) } }

        case kind
        when "formLogin"
          # Without `loginProcessingUrl` the filter listens on the login page URL.
          next if unknown.includes?("loginProcessingUrl") || (!values.has_key?("loginProcessingUrl") && unknown.includes?("loginPage"))
          url = values["loginProcessingUrl"]? || values["loginPage"]? || "/login"
          params = [] of String
          params << (values["usernameParameter"]? || "username") unless unknown.includes?("usernameParameter")
          params << (values["passwordParameter"]? || "password") unless unknown.includes?("passwordParameter")
          routes << {"POST", url, params, offset, nil, served.call(url)}
        when "logout"
          verb = "POST"
          if matcher = masked_scope.match(/\blogoutRequestMatcher\s*(?:\(|=)/)
            next unless found = scope[matcher.end(0)..].match(SPRING_LOGOUT_MATCHER_RE)
            url = found[1]
            verb = found[2]? || found[3]? || "ANY"
          else
            next if unknown.includes?("logoutUrl")
            url = values["logoutUrl"]? || "/logout"
          end
          success = masked_scope.match(SPRING_LOGOUT_SUCCESS_RE).try { |handler| handler[1]? || handler[2]? }
          routes << {verb, url, [] of String, offset, success, served.call(url)}
        when "oauth2Login"
          authorization = spring_security_sub_values(scope, masked_scope, code, "authorizationEndpoint")
          redirection = spring_security_sub_values(scope, masked_scope, code, "redirectionEndpoint")
          unless authorization.is_a?(Bool)
            url = Noir::URLPath.join_rooted(authorization || "/oauth2/authorization", "{registrationId}")
            routes << {"GET", url, [] of String, offset, nil, served.call(url)}
          end
          unless redirection.is_a?(Bool)
            # The redirection `baseUri` is an Ant pattern; its `*` is the registration id.
            redirection ||= "/login/oauth2/code/*"
            callback = redirection.ends_with?('*') ? Noir::URLPath.join_rooted(redirection.rchop('*'), "{registrationId}") : redirection
            routes << {"GET", callback, ["code", "state"], offset, nil, served.call(callback)}
          end
        end
      end
      routes
    end

    # Whether the DSL call at `offset` configures an `HttpSecurity`: a
    # dotted call's chain (`http.csrf(..).logout(..)`, `.and()` hops
    # included) starts at one of the `receivers` variables, and a Kotlin
    # block (`logout { }`) sits inside `http { }`. `tokenService.logout(t)`
    # does not.
    private def self.spring_security_receiver?(chars : Array(Char), offset : Int32, dotted : Bool, receivers : Set(String)) : Bool
      if dotted
        pos = offset
        loop do
          i = skip_space_back(chars, pos - 1)
          if i >= 0 && chars[i] == ')'
            depth = 0
            while i >= 0
              depth += 1 if chars[i] == ')'
              depth -= 1 if chars[i] == '('
              break if depth.zero?
              i -= 1
            end
            i = skip_space_back(chars, i - 1)
          end
          stop = i
          while i >= 0 && (chars[i].alphanumeric? || chars[i] == '_' || chars[i] == '$')
            i -= 1
          end
          return false if i == stop
          j = skip_space_back(chars, i)
          return receivers.includes?(chars[(i + 1)..stop].join) unless j >= 0 && chars[j] == '.'
          pos = j
        end
      else
        depth = 0
        i = offset - 1
        while i >= 0
          case chars[i]
          when '}' then depth += 1
          when '{'
            if depth.zero?
              stop = skip_space_back(chars, i - 1)
              start = stop
              while start >= 0 && (chars[start].alphanumeric? || chars[start] == '_' || chars[start] == '$')
                start -= 1
              end
              return true if start < stop && receivers.includes?(chars[(start + 1)..stop].join)
            else
              depth -= 1
            end
          end
          i -= 1
        end
        false
      end
    end

    private def self.skip_space_back(chars : Array(Char), index : Int32) : Int32
      while index >= 0 && chars[index].whitespace?
        index -= 1
      end
      index
    end

    # The literal patterns of the `securityMatcher` that scopes the chain
    # holding `offset`; nil when the chain is not scoped. A matcher noir
    # cannot read gives an empty list: no URL is known to be inside it.
    private def self.spring_chain_patterns(code : String, masked : String, offset : Int32) : Array(String)?
      from, to = spring_chain_range(masked, offset)
      chain = masked[from...to]
      patterns : Array(String)? = nil
      chain.scan(SPRING_CHAIN_SCOPE_RE) do |call|
        patterns ||= [] of String
        close_from, close_to = spring_security_scope(chain, call.end(0) - 1)
        code[(from + close_from)...(from + close_to)].scan(JAVA_STRING_RE) { |literal| patterns << literal[0][1..-2] }
      end
      patterns
    end

    # The char range of the security chain (bean method) holding `offset`.
    def self.spring_chain_range(masked : String, offset : Int32) : {Int32, Int32}
      from = 0
      to = masked.size
      masked.scan(SPRING_CHAIN_START_RE) do |boundary|
        if boundary.begin(0) <= offset
          from = boundary.begin(0)
        else
          to = boundary.begin(0)
          break
        end
      end
      {from, to}
    end

    # Spring's ant match of a request path (`/**` also matches the bare prefix).
    def self.ant_matches?(url : String, pattern : String) : Bool
      pattern = "/#{pattern}" unless pattern.starts_with?('/')
      escaped = Regex.escape(pattern).sub(/\/\\\*\\\*\z/, "(?:/.*)?").gsub("\\*\\*", ".*").gsub("\\*", "[^/]*")
      url.matches?(/\A#{escaped}\/?\z/)
    end

    # The `(from, to)` char range of the configuration a DSL call at
    # `open_idx` (its `(` or `{`) applies: the lambda / Kotlin block body,
    # or — for the legacy `formLogin()` chain — the calls after it up to
    # `.and()` or the statement end.
    #
    # ponytail: a legacy chain that hops sub-configurers with `.and()`
    # (`oauth2Login().authorizationEndpoint()...and().redirectionEndpoint()`)
    # is cut at the first `.and()`; that style is deprecated.
    private def self.spring_security_scope(code : String, open_idx : Int32) : {Int32, Int32}
      open_char = code[open_idx]
      close_char = open_char == '(' ? ')' : '}'
      depth = 0
      close_idx = nil
      JavaEngine.each_char_after(code, open_idx - 1) do |c, i|
        depth += 1 if c == open_char
        depth -= 1 if c == close_char
        if depth.zero?
          close_idx = i
          break
        end
      end
      return {open_idx + 1, code.size} unless close_idx
      return {open_idx + 1, close_idx} unless code[(open_idx + 1)...close_idx].blank?
      rest = code[(close_idx + 1)..]
      cut = [rest.index(".and()"), rest.index(';')].compact.min?
      {close_idx + 1, cut ? close_idx + 1 + cut : code.size}
    end

    # The `baseUri` of the `name` sub-configurer (`authorizationEndpoint`):
    # nil when unset, false when set to a value noir cannot read.
    private def self.spring_security_sub_values(scope : String, masked_scope : String, code : String, name : String) : (String | Bool)?
      return unless match = masked_scope.match(/\b#{name}\s*([({])/)
      from, to = spring_security_scope(masked_scope, match.begin(1))
      values, unknown = spring_security_values(scope[from...to], masked_scope[from...to], code)
      return false if unknown.includes?("baseUri")
      values["baseUri"]?
    end

    # The first value of each configurer setter in `scope`, and the setters
    # given a value noir cannot read.
    private def self.spring_security_values(scope : String, masked_scope : String, code : String) : {Hash(String, String), Set(String)}
      values = Hash(String, String).new
      unknown = Set(String).new
      masked_scope.scan(SPRING_SECURITY_SETTER_RE) do |match|
        key = match[1]
        next if values.has_key?(key) || unknown.includes?(key)
        argument = scope[match.end(0)..]
        if literal = argument.match(/\A"((?:[^"\\]|\\.)*)"/)
          values[key] = literal[1]
        elsif (constant = argument.match(/\A([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\s*[),;}\n]/)) &&
              (name = constant[1].split('.').last) &&
              (declared = code.match(/\b(?:static\s+final\s+String|final\s+static\s+String|const\s+val)\s+#{Regex.escape(name)}\s*(?::\s*String\s*)?=\s*"((?:[^"\\]|\\.)*)"/))
          values[key] = declared[1]
        else
          unknown << key
        end
      end
      {values, unknown}
    end

    private def spring_security_endpoints(path : String, base_path : String) : Array(Endpoint)
      content = read_file_content(path)
      return [] of Endpoint unless content_matches?(content, SPRING_SECURITY_FILE_RE)
      code = JavaEngine.strip_comments(content)
      JavaEngine.spring_security_routes(code).map do |verb, url, params, offset, success, served|
        endpoint = framework_endpoint(
          Noir::URLPath.join_rooted(base_path, url), verb, PathInfo.new(path, line_number_for_index(code, offset)),
          params.map { |name| Param.new(name, "", verb == "POST" ? "form" : "query") }, served ? SECURITY_FILTER_TAG : FRAMEWORK_PROVIDED_TAG
        )
        endpoint.handler = logout_success_handler(success, code, offset) if success
        endpoint
      end
    end

    # `Impl.onLogoutSuccess` of the project class a logout route's success
    # handler is: `new Impl()`, or a variable declared as `Impl x` / `x: Impl`
    # — the last declaration before the DSL call at `offset` (the chain
    # method's parameter, else a field), the type fully qualified or
    # resolved by import. A variable typed by the interface, or a class
    # outside the project, has no definition to point at.
    private def logout_success_handler(written : String, code : String, offset : Int32) : Handler?
      type = if written[0].uppercase? || written.includes?('.')
               written
             else
               spring_variable_type(written, code, offset)
             end
      return unless type
      return unless file = JavaEngine.java_type_file(type, code)
      source = JavaEngine.strip_comments(read_file_content(file))
      return unless found = source.match(/\b(?:void|fun)\s+onLogoutSuccess\s*\(/)
      Handler.new("#{type.split('.').last}.onLogoutSuccess", file, line_number_for_index(source, found.begin(0)))
    end

    # The declared type of `variable` as the DSL call at `offset` sees it: a
    # declaration in the same chain method before the call (its parameter or
    # a local), else a field of the class (`Impl x;` / Kotlin `val x: Impl`
    # constructor property). Another method's same-named parameter is not it.
    private def spring_variable_type(variable : String, code : String, offset : Int32) : String?
      masked = code.gsub(JAVA_STRING_RE) { |literal| "\"#{" " * (literal.size - 2)}\"" }
      chain_from, _ = JavaEngine.spring_chain_range(masked, offset)
      escaped = Regex.escape(variable)
      in_chain = nil
      field = nil
      masked.scan(/\b((?:[a-z_$][\w$]*\.)*[A-Z][\w$]*)(?:<[^<>]*>)?\s+#{escaped}\s*[;=,)]|\b(?:va[lr]\s+)?#{escaped}\s*:\s*((?:[a-z_$][\w$]*\.)*[A-Z][\w$]*)\b/) do |found|
        at = found.begin(0)
        type = found[1]? || found[2]
        if chain_from <= at < offset
          in_chain = type
        elsif field.nil? && class_member_level?(masked, at, found[0].starts_with?("val") || found[0].starts_with?("var"))
          field = type
        end
      end
      in_chain || field
    end

    # Whether `at` is a class member declaration: directly in a class body
    # (one brace deep, outside parentheses), or a Kotlin constructor
    # property (`class S(private val x: Impl)`).
    private def class_member_level?(masked : String, at : Int32, kotlin_property : Bool) : Bool
      braces = 0
      parens = 0
      masked.each_char_with_index do |char, index|
        break if index >= at
        case char
        when '{' then braces += 1
        when '}' then braces -= 1
        when '(' then parens += 1
        when ')' then parens -= 1
        end
      end
      (braces == 1 && parens == 0) || (kotlin_property && braces == 0 && parens == 1)
    end

    # Every file under a resolved static-resource directory is a GET
    # endpoint. The walk is a `Dir.glob` rather than a `file_map` lookup
    # because the endpoint set is "every file under this directory",
    # including the images and fonts the media filter keeps out of the
    # index (and dotfiles like `.env.prod`) — so `--exclude-path` has to be
    # re-applied here by hand.
    private def spring_static_endpoints(project_root : String, values : Hash(String, String), base_path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      configured = values["spring.web.resources.static-locations"]? || values["spring.resources.static-locations"]?
      locations = configured.try(&.split(',').map(&.strip).reject(&.empty?))
      locations = SPRING_DEFAULT_STATIC_LOCATIONS if locations.nil? || locations.empty?

      locations.each do |location|
        dir = if location.starts_with?("classpath:")
                File.join(project_root, "src/main/resources", location.sub("classpath:", "").strip)
              elsif location.starts_with?("file:")
                location.sub("file:", "").strip
              end
        next unless dir && Dir.exists?(dir)
        # The location comes verbatim from the app's own config, so it can
        # point anywhere: `file:/etc/` is an absolute path, and a
        # `classpath:/../../../x/` climbs out of `src/main/resources`.
        # Walking it emitted an endpoint per file outside the scan, with
        # `code_paths` leaking the scanning machine's layout into a report
        # that may be shared.
        unless within_scan_base?(dir)
          logger.debug "Skipping static-location #{location}: resolves outside the scan base"
          next
        end
        Dir.glob("#{escape_glob_path(dir)}/**/*", match: File::MatchOptions::DotFiles) do |file|
          next if File.directory?(file) || excluded_path?(file)
          url = Noir::URLPath.absolute_join(base_path, file.sub(dir, ""))
          endpoints << Endpoint.new(url, "GET", Details.new(PathInfo.new(file)))
        end
      end

      endpoints
    end

    # The Maven/Gradle module root: everything above the source root that
    # holds this file. Default for includers; JAX-RS and Helidon MP
    # override it, and `JavaEngine.project_root_for` above is the variant
    # Micronaut and Dropwizard call.
    private def project_root_for(path : String) : String
      base = configured_base_for(path)
      Noir::PathScope.marker_root(path, base, {"/src/main/java/", "/src/main/kotlin/", "/src/"}) || base
    end

    # A file that declares no `static final String` and no interface (whose
    # fields are implicitly static final) has no constant another file
    # could reference.
    JAVA_STRING_CONSTANT_RE = /\bstatic\s+final\s+(?:java\.lang\.)?String\b|\bfinal\s+static\s+(?:java\.lang\.)?String\b|\binterface\s/

    @java_project_constants : Hash(String, Hash(String, String))? = nil

    # Qualified (`Paths.API`, `com.ex.Paths.API`) String constants from
    # every `.java` source under `path`'s configured base, so a controller
    # can use a constant declared in another class or interface. One pass
    # per analyzer run; the per-file tables are memoized by content in
    # `TreeSitterJavaRouteExtractor.extract_string_constants`, so analyzers
    # sharing a scan parse each file once. Bare names stay file-local —
    # merging them project-wide would let unrelated classes collide.
    #
    # ponytail: same-simple-name classes in different packages share the
    # `Class.NAME` key (first one wins); key on imports if that bites.
    private def java_project_constants(path : String) : Hash(String, String)
      tables = @java_project_constants ||= begin
        by_base = Hash(String, Hash(String, String)).new
        get_files_by_extension(".java").each do |file|
          next if JavaEngine.test_path?(base_relative_path(file))
          content = read_file_content(file)
          next unless content_matches?(content, JAVA_STRING_CONSTANT_RE)
          table = by_base[configured_base_for(file)] ||= Noir::TreeSitterJavaRouteExtractor::ProjectConstants.new
          Noir::TreeSitterJavaRouteExtractor.extract_string_constants(content).each do |name, value|
            table[name] ||= value if name.includes?('.')
          end
        end
        by_base
      end
      tables[configured_base_for(path)]? || Hash(String, String).new
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
