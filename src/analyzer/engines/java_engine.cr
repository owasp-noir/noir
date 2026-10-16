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
    # `integrationTest`, `functionalTest`).
    TEST_SOURCE_SET_RE = Regex.union(
      "/src/test/",
      "/src/it/",
      "/src/testFixtures/",
      "/src/jmh/",
      "/src/integrationTest/",
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

    private def framework_endpoint(url : String, verb : String, evidence : PathInfo, params = [] of Param) : Endpoint
      endpoint = Endpoint.new(url, verb, params, Details.new(evidence))
      endpoint.add_tag(FRAMEWORK_PROVIDED_TAG)
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
    # DSL's `formLogin {` — a bare `logout(` is any app's own method.
    SPRING_SECURITY_DSL_RE   = /(?:\.\s*(formLogin|logout|oauth2Login)\s*\(|\b(formLogin|logout|oauth2Login)\s*\{)/
    SPRING_SECURITY_VALUE_RE = /\b(loginPage|loginProcessingUrl|usernameParameter|passwordParameter|logoutUrl|baseUri)\s*(?:\(\s*|=\s*)"([^"\\]*)"/

    # verb, path, form params, offset of the DSL call in `code`.
    alias SpringSecurityRoute = Tuple(String, String, Array(String), Int32)

    # The login / logout / OAuth2 endpoints Spring Security's filters serve
    # for each `formLogin` / `logout` / `oauth2Login` in a security chain,
    # with the configured URLs and parameter names or Spring's defaults.
    # `code` is comment-stripped source. Only string literals are read.
    def self.spring_security_routes(code : String) : Array(SpringSecurityRoute)
      routes = [] of SpringSecurityRoute
      code.scan(SPRING_SECURITY_DSL_RE) do |match|
        kind = match[1]? || match[2]
        open_idx = match.end(0) - 1
        scope = spring_security_scope(code, open_idx)
        next if scope.matches?(/\bdisable\b/)
        values = spring_security_values(scope)
        offset = match.begin(0)

        case kind
        when "formLogin"
          # Without `loginProcessingUrl` the filter listens on the login page URL.
          url = values["loginProcessingUrl"]? || values["loginPage"]? || "/login"
          routes << {"POST", url, [values["usernameParameter"]? || "username", values["passwordParameter"]? || "password"], offset}
        when "logout"
          routes << {"POST", values["logoutUrl"]? || "/logout", [] of String, offset}
        when "oauth2Login"
          authorization = spring_security_sub_scope(scope, "authorizationEndpoint").try { |sub| spring_security_values(sub)["baseUri"]? }
          redirection = spring_security_sub_scope(scope, "redirectionEndpoint").try { |sub| spring_security_values(sub)["baseUri"]? }
          routes << {"GET", Noir::URLPath.join_rooted(authorization || "/oauth2/authorization", "{registrationId}"), [] of String, offset}
          # The redirection `baseUri` is an Ant pattern; its `*` is the registration id.
          redirection ||= "/login/oauth2/code/*"
          callback = redirection.ends_with?('*') ? Noir::URLPath.join_rooted(redirection.rchop('*'), "{registrationId}") : redirection
          routes << {"GET", callback, ["code", "state"], offset}
        end
      end
      routes
    end

    # The configuration a DSL call at `open_idx` (its `(` or `{`) applies:
    # the lambda / Kotlin block body, or — for the legacy `formLogin()`
    # chain — the calls after it up to `.and()` or the statement end.
    #
    # ponytail: a legacy chain that hops sub-configurers with `.and()`
    # (`oauth2Login().authorizationEndpoint()...and().redirectionEndpoint()`)
    # is cut at the first `.and()`; that style is deprecated.
    private def self.spring_security_scope(code : String, open_idx : Int32) : String
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
      return code[(open_idx + 1)..] unless close_idx
      inner = code[(open_idx + 1)...close_idx]
      return inner unless inner.blank?
      rest = code[(close_idx + 1)..]
      cut = [rest.index(".and()"), rest.index(';')].compact.min?
      cut ? rest[0, cut] : rest
    end

    private def self.spring_security_sub_scope(scope : String, name : String) : String?
      return unless match = scope.match(/\b#{name}\s*([({])/)
      spring_security_scope(scope, match.begin(1))
    end

    # First literal value of each configurer setter in `scope`.
    private def self.spring_security_values(scope : String) : Hash(String, String)
      values = Hash(String, String).new
      scope.scan(SPRING_SECURITY_VALUE_RE) { |match| values[match[1]] ||= match[2] }
      values
    end

    private def spring_security_endpoints(path : String, base_path : String) : Array(Endpoint)
      content = read_file_content(path)
      return [] of Endpoint unless content_matches?(content, SPRING_SECURITY_FILE_RE)
      code = JavaEngine.strip_comments(content)
      JavaEngine.spring_security_routes(code).map do |verb, url, params, offset|
        framework_endpoint(
          Noir::URLPath.join_rooted(base_path, url), verb, PathInfo.new(path, line_number_for_index(code, offset)),
          params.map { |name| Param.new(name, "", verb == "POST" ? "form" : "query") }
        )
      end
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
