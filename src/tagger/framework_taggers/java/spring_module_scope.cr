require "../../../models/framework_tagger"
require "../../../utils/c_comments"
require "../../../utils/js_literal_scanner"
require "../../../utils/top_level_split"
require "../../../utils/url_path"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../analyzer/engines/java_engine"

# Which build units' Spring beans serve an endpoint. A `SecurityFilterChain`,
# a `csrf` setting or a CORS mapping lives in one Maven / Gradle module and
# applies only to the apps whose runtime classpath holds that module, so
# `spring_auth` and `spring_security` judge an endpoint once per app that
# serves it (`per_serving_classpath`). Both read a chain's request matchers
# the same way (`chain_scope`, `matcher_patterns`).
module SpringModuleScope
  BUILD_FILE       = /\A(?:pom\.xml|build\.gradle(?:\.kts)?)\z/
  BOOT_APP_MARKERS = {"@SpringBootApplication", "@SpringBootConfiguration", "SpringApplication.run", "runApplication<"}

  # Build units holding a Boot entry point; the including tagger fills it
  # from its pre-scan through `note_boot_app`.
  @boot_apps = Set(String).new

  private def note_boot_app(file : String, content : String)
    return if file.includes?("/src/test/") || BOOT_APP_MARKERS.none? { |marker| content.includes?(marker) }
    build_module(file).try { |app| @boot_apps << app }
  end

  # The build unit (directory of the nearest `pom.xml` / `build.gradle`)
  # holding `path`; nil when there is none.
  private def build_module(path : String) : String?
    nearest_project_root(path, BUILD_FILE)
  end

  # The build units of the endpoint's sources. A build file is no evidence
  # of the serving module: a framework-provided route (`/actuator`) points
  # at the parent pom that declares the dependency every child app inherits.
  private def endpoint_modules(endpoint : Endpoint) : Array(String)
    endpoint.details.code_paths.compact_map do |path_info|
      path = path_info.path
      build_module(path) unless MediaFilter.spec_document?(path) || File.basename(path).matches?(BUILD_FILE)
    end.uniq!
  end

  # The first truthy result of the block for each app serving `endpoint`:
  # its runtime classpath (nil: unknown, every unit's beans apply) and its
  # module directory (nil when the endpoint has no build unit). A module
  # whose classpath noir cannot read gets `Set{module_dir}` when
  # `own_module_when_unknown`, nil otherwise.
  private def per_serving_classpath(endpoint : Endpoint, own_module_when_unknown : Bool, &)
    modules = endpoint_modules(endpoint)
    return yield nil, nil if modules.empty?

    modules.each do |module_dir|
      if apps = serving_apps(module_dir)
        apps.each do |app|
          if decision = yield module_classpath(app).try(&.[0]), app
            return decision
          end
        end
      elsif decision = yield (own_module_when_unknown ? Set{module_dir} : nil), module_dir
        return decision
      end
    end
    nil
  end

  @serving_apps = Hash(String, Array(String)?).new

  # The modules whose runtime classpath holds `module_dir`: itself and every
  # module depending on it, narrowed to the Boot entry points
  # when there are any. Nil when `module_dir`'s classpath is unknown. A
  # Boot app is not taken as served by a module whose classpath is only
  # its whole build (`gradle_build`): that is no evidence it depends on it.
  private def serving_apps(module_dir : String) : Array(String)?
    return @serving_apps[module_dir] if @serving_apps.has_key?(module_dir)
    @serving_apps[module_dir] = if module_classpath(module_dir)
                                  boot_app = @boot_apps.includes?(module_dir)
                                  hosts = build_modules.select do |dir|
                                    module_classpath(dir).try(&.[0].includes?(module_dir)) &&
                                      !(boot_app && dir != module_dir && @whole_build_classpaths.includes?(dir))
                                  end
                                  hosts << module_dir unless hosts.includes?(module_dir)
                                  runnable = hosts.select { |dir| @boot_apps.includes?(dir) }
                                  runnable.empty? ? hosts : runnable
                                end
  end

  @build_modules : Array(String)? = nil

  # Directories of every `pom.xml` / `build.gradle(.kts)` in the scan.
  private def build_modules : Array(String)
    @build_modules ||= {"pom.xml", "build.gradle", "build.gradle.kts"}.flat_map do |name|
      CodeLocator.instance.files_by_basename(name).map { |file| File.dirname(Noir::PathScope.expand(file)) }
    end.uniq!
  end

  alias MavenDependency = NamedTuple(artifact: String, scope: String?, optional: Bool)
  alias MavenPom = NamedTuple(parent: String?, dependencies: Array(MavenDependency))

  @maven_modules : Hash(String, Array(String))? = nil
  @maven_poms = Hash(String, MavenPom?).new
  @module_classpaths = Hash(String, {Set(String), Bool}?).new

  # Comments, version pins (`dependencyManagement`), plugin dependencies
  # (`build`) and exclusions name no dependency of the module.
  MAVEN_NOISE       = /<!--.*?-->|<dependencyManagement>.*?<\/dependencyManagement>|<build>.*?<\/build>|<exclusions>.*?<\/exclusions>/m
  MAVEN_ARTIFACT_ID = /<artifactId>\s*([^<\s]+)\s*<\/artifactId>/
  MAVEN_DEPENDENCY  = /<dependency>(.*?)<\/dependency>/m
  MAVEN_PARENT      = /<parent>(.*?)<\/parent>/m

  SPRING_SECURITY_ARTIFACT = /\A(?:spring-boot-starter-security|spring-security-(?!test\z)[\w.-]+|spring-boot-starter-oauth2-[\w.-]+)\z/

  # `{module directories on module_dir's runtime classpath (itself
  # included), whether Spring Security is on it}`; nil when unknown (a
  # dependency cycle between Maven and Gradle builds included).
  private def module_classpath(module_dir : String) : {Set(String), Bool}?
    return @module_classpaths[module_dir] if @module_classpaths.has_key?(module_dir)
    return unless @classpaths_pending.add?(module_dir)
    begin
      @module_classpaths[module_dir] = File.exists?(File.join(module_dir, "pom.xml")) ? maven_classpath(module_dir) : gradle_classpath(module_dir)
    ensure
      @classpaths_pending.delete(module_dir)
    end
  end

  @classpaths_pending = Set(String).new

  # By Maven's rules: a parent's dependencies are the module's own; a
  # dependency's own dependencies come along unless `optional`; `test`
  # scope never reaches the runtime. A dependency on a Gradle module of the
  # scan brings that module's classpath.
  private def maven_classpath(module_dir : String) : {Set(String), Bool}?
    dirs = Set(String).new
    security = false
    seen = Set({String, Bool}).new
    queue = [{module_dir, true}]
    while item = queue.shift?
      next unless seen.add?(item)
      dir, direct = item
      return unless pom = maven_pom(dir)
      dirs << dir
      pom[:parent].try { |parent| maven_modules[parent]?.try(&.each { |parent_dir| queue << {parent_dir, direct} }) }
      pom[:dependencies].each do |dependency|
        next if dependency[:scope] == "test" || (dependency[:optional] && !direct)
        security ||= dependency[:artifact].matches?(SPRING_SECURITY_ARTIFACT)
        if maven_dirs = maven_modules[dependency[:artifact]]?
          maven_dirs.each { |dependency_dir| queue << {dependency_dir, false} }
        else
          gradle_artifacts[dependency[:artifact]]?.try &.each do |gradle_dir|
            next if dirs.includes?(gradle_dir)
            return unless found = module_classpath(gradle_dir)
            dirs.concat(found[0])
            security ||= found[1]
          end
        end
      end
    end
    {dirs, security}
  end

  private def maven_pom(dir : String) : MavenPom?
    return @maven_poms[dir] if @maven_poms.has_key?(dir)
    path = File.join(dir, "pom.xml")
    @maven_poms[dir] = if File.exists?(path) && (content = read_file(path))
                         code = content.gsub(MAVEN_NOISE, "")
                         parent = code.match(MAVEN_PARENT).try { |block| block[1].match(MAVEN_ARTIFACT_ID).try(&.[1]) }
                         dependencies = code.scan(MAVEN_DEPENDENCY).compact_map do |block|
                           next unless artifact = block[1].match(MAVEN_ARTIFACT_ID)
                           {artifact: artifact[1], scope: block[1].match(/<scope>\s*([^<\s]+)/).try(&.[1]), optional: block[1].matches?(/<optional>\s*true\s*</)}
                         end
                         {parent: parent, dependencies: dependencies}
                       end
  end

  # artifactId => directories of the project modules declaring it.
  private def maven_modules : Hash(String, Array(String))
    @maven_modules ||= begin
      index = Hash(String, Array(String)).new
      CodeLocator.instance.files_by_basename("pom.xml").each do |pom|
        next unless content = read_file(pom)
        own = content.gsub(MAVEN_NOISE, "").gsub(MAVEN_PARENT, "").match(MAVEN_ARTIFACT_ID)
        (index[own[1]] ||= [] of String) << File.dirname(Noir::PathScope.expand(pom)) if own
      end
      index
    end
  end

  GRADLE_SETTINGS = /\Asettings\.gradle(?:\.kts)?\z/
  # `project(":a:b")`, `project(path: ':a')`, and the type-safe accessor
  # `projects.a.b`.
  GRADLE_PROJECT_REF      = /\bproject\s*\(\s*(?:path\s*[:=]\s*)?["']([^"']+)["']/
  GRADLE_PROJECT_ACCESSOR = /\bprojects\s*\.\s*([A-Za-z_][\w.]*)/
  # Any project dependency, read or not (`project(mapOf("path" to ":a"))`).
  GRADLE_PROJECT_MENTION = /\bproject\s*\(|\bprojects\s*\.\s*[A-Za-z_]/
  # A coordinate `"group:name[:version]"`: a module of another build in the
  # scan when `name` is that module's directory or Maven artifactId.
  GRADLE_COORDINATE = /["'][\w.-]+:([\w.-]+)(?::[^"'\s]*)?["']/
  # Spring Security named by a coordinate or a version-catalog accessor
  # (`libs.spring.boot.starter.security`), not its test kit or BOM.
  GRADLE_SPRING_SECURITY = /spring[-._]?(?:boot[-._]?starter[-._]?(?:security|oauth2)|security(?![-._]?(?:test|bom)\b))/i
  # A line that adds a dependency, not a version constraint (`force`,
  # `includeVersion`) or a plugin classpath.
  GRADLE_DEPENDENCY_LINE = /\b(?:implementation|api|compile|runtime|runtimeOnly|developmentOnly|add)\b/
  # `project(":x").projectDir = file("libs/x")` (or `File(rootDir, "libs/x")`).
  GRADLE_PROJECT_DIR       = /\bproject\s*\(\s*["']([^"']+)["']\s*\)\s*\.\s*projectDir\s*=\s*(?:file\s*\(|(?:new\s+)?File\s*\(\s*\w+\s*,)\s*["']([^"']+)["']/
  GRADLE_ROOT_PROJECT_NAME = /\brootProject\.name\s*=\s*["']([^"']+)["']/
  GRADLE_CONFIGURATION     = /\A\s*([A-Za-z_]\w*)/
  GRADLE_SCRIPT_EXTENSION  = /\.gradle(?:\.kts)?\z/
  # Precompiled convention plugins.
  GRADLE_BUILD_LOGIC_DIR = /\/(?:buildSrc|build-logic)\//

  # What one Gradle script says outside test configurations: its
  # `{project path or coordinate name, is project}` dependencies, whether it
  # names Spring Security, and whether it names a project at all.
  record GradleScript, refs : Array({String, Bool}), security : Bool, mentions_project : Bool

  @gradle_scripts = Hash(String, GradleScript?).new

  private def gradle_script(path : String) : GradleScript?
    return @gradle_scripts[path] if @gradle_scripts.has_key?(path)
    @gradle_scripts[path] = if content = existing_file(path)
                              code = Noir::CComments.strip(content)
                              refs = [] of {String, Bool}
                              security = false
                              mentions = false
                              code.each_line do |line|
                                next if line.match(GRADLE_CONFIGURATION).try(&.[1].downcase.includes?("test"))
                                security ||= line.matches?(GRADLE_DEPENDENCY_LINE) && line.matches?(GRADLE_SPRING_SECURITY)
                                mentions ||= line.matches?(GRADLE_PROJECT_MENTION)
                                read = refs.size
                                line.scan(GRADLE_PROJECT_REF) { |match| refs << {normalize_gradle_path(match[1]), true} }
                                line.scan(GRADLE_PROJECT_ACCESSOR) { |match| refs << {normalize_gradle_path(match[1].tr(".", ":")), true} }
                                # A project dependency noir cannot read resolves to nothing.
                                refs << {"?", true} if refs.size == read && line.matches?(GRADLE_PROJECT_MENTION)
                                line.scan(GRADLE_COORDINATE) { |match| refs << {match[1], false} }
                              end
                              GradleScript.new(refs, security, mentions)
                            end
  end

  private def gradle_build_script(dir : String) : GradleScript?
    gradle_script(File.join(dir, "build.gradle")) || gradle_script(File.join(dir, "build.gradle.kts"))
  end

  # By Gradle's rules: the module and, transitively, the `project(...)`
  # dependencies of its build file outside test configurations. Separate
  # builds (no shared `settings.gradle`) share nothing but coordinate
  # dependencies on each other. When noir cannot tell the classpath is
  # complete it does not narrow it: every module of the build when a root
  # build file or a script or convention plugin names a project (as
  # `subprojects {}` does), and nil (unknown) when a project reference does
  # not resolve or a settings file sits above the scan.
  private def gradle_classpath(module_dir : String) : {Set(String), Bool}?
    return if gradle_settings_above_scan?
    roots = gradle_roots(module_dir)
    if opaque = roots.reverse.find { |root| gradle_opaque?(root, module_dir) }
      @whole_build_classpaths << module_dir
      return gradle_build(opaque, module_dir)
    end

    dirs = Set(String).new
    security = roots.any? { |root| gradle_root_security?(root) }
    queue = [module_dir]
    while dir = queue.shift?
      next unless dirs.add?(dir)
      next unless script = gradle_build_script(dir)
      security ||= script.security
      script.refs.each do |ref, project|
        if project
          return unless target = roots.compact_map { |root| gradle_projects(root)[ref]? }.first?
          queue << target
        else
          gradle_artifacts[ref]?.try &.each do |target|
            next if dirs.includes?(target)
            return unless found = module_classpath(target)
            dirs.concat(found[0])
            security ||= found[1]
          end
        end
      end
    end
    {dirs, security}
  end

  @whole_build_classpaths = Set(String).new
  @gradle_roots = Hash(String, Array(String)).new

  # The directories holding a `settings.gradle` from `module_dir` up to the
  # scan base, nearest first: a sample's own settings file can sit inside
  # the build that includes it.
  private def gradle_roots(module_dir : String) : Array(String)
    @gradle_roots[module_dir] ||= begin
      bases = @base_paths.map { |base| Noir::PathScope.normalize_root(base) }
      roots = [] of String
      dir = module_dir
      while root = nearest_project_root(File.join(dir, "build.gradle"), GRADLE_SETTINGS)
        roots << root
        parent = File.dirname(root)
        break if bases.includes?(root) || parent == root
        dir = parent
      end
      roots
    end
  end

  @gradle_settings_above_scan : Bool? = nil

  # A settings file above a scan base: the scan holds part of a build whose
  # root build file it cannot read.
  private def gradle_settings_above_scan? : Bool
    @gradle_settings_above_scan = begin
      @base_paths.reject(&.empty?).any? do |base|
        Path[Noir::PathScope.normalize_root(base)].parents.any? do |dir|
          File.exists?(dir.join("settings.gradle")) || File.exists?(dir.join("settings.gradle.kts"))
        end
      end
    end if @gradle_settings_above_scan.nil?
    @gradle_settings_above_scan || false
  end

  # Every module of the build rooted at `root`, as `module_dir`'s classpath.
  # Spring Security is on it only when the root build file, the build
  # logic or the module's own build file names it: another module of the
  # build is not known to be a dependency.
  private def gradle_build(root : String, module_dir : String) : {Set(String), Bool}
    dirs = Set.new(build_modules.select { |dir| Noir::PathScope.under_root?(dir, root) })
    {dirs, gradle_root_security?(root) || gradle_build_script(module_dir).try(&.security) || false}
  end

  # Whether something besides `module_dir`'s own build file can add a
  # project dependency to it in the build rooted at `root`: the root build
  # file (unless it is the module's own) or the build logic.
  private def gradle_opaque?(root : String, module_dir : String) : Bool
    (root != module_dir && gradle_build_script(root).try(&.mentions_project)) ||
      gradle_build_logic.any? { |path, script| script.mentions_project && path.starts_with?("#{root}/") }
  end

  # Whether the root build file or the build logic of `root` names Spring
  # Security (a `subprojects {}` dependency, a convention plugin).
  private def gradle_root_security?(root : String) : Bool
    gradle_build_script(root).try(&.security) || gradle_build_logic.any? { |path, script| script.security && path.starts_with?("#{root}/") }
  end

  @gradle_build_logic : Array({String, GradleScript})? = nil

  # Gradle scripts that are neither a build nor a settings file (`apply
  # from:` scripts, precompiled script plugins) and the sources of
  # `buildSrc` / `build-logic` convention plugins.
  private def gradle_build_logic : Array({String, GradleScript})
    @gradle_build_logic ||= {".gradle", ".kts", ".kt", ".groovy", ".java"}.flat_map do |ext|
      collect_files_by_extension(ext).compact_map do |file|
        path = Noir::PathScope.expand(file)
        base = File.basename(path)
        next if base.matches?(BUILD_FILE) || base.matches?(GRADLE_SETTINGS)
        build_logic = base.matches?(GRADLE_SCRIPT_EXTENSION) || (path.matches?(GRADLE_BUILD_LOGIC_DIR) && !path.includes?("/src/test/"))
        next unless build_logic
        gradle_script(path).try { |script| {path, script} }
      end
    end
  end

  @gradle_projects = Hash(String, Hash(String, String)).new

  # Normalized project path (`a:b`) => directory, for the build rooted at
  # `root`. A `projectDir` remap noir cannot place (`"$rootDir/x"`, a
  # directory without a build file) is left out, so a reference to it does
  # not resolve.
  private def gradle_projects(root : String) : Hash(String, String)
    @gradle_projects[root] ||= begin
      index = {"" => root}
      build_modules.each do |dir|
        index[normalize_gradle_path(dir[(root.size + 1)..].tr("/", ":"))] = dir if dir.starts_with?("#{root}/")
      end
      {"settings.gradle", "settings.gradle.kts"}.each do |name|
        next unless content = existing_file(File.join(root, name))
        Noir::CComments.strip(content).scan(GRADLE_PROJECT_DIR) do |match|
          dir = File.expand_path(match[2], root)
          key = normalize_gradle_path(match[1])
          if match[2].includes?('$') || !build_modules.includes?(dir)
            index.delete(key)
          else
            index[key] = dir
          end
        end
      end
      index
    end
  end

  @gradle_artifacts : Hash(String, Array(String))? = nil

  # Module name (directory, `rootProject.name`, Maven artifactId) =>
  # directories, for coordinate dependencies between builds (an
  # `includeBuild` composite among them).
  private def gradle_artifacts : Hash(String, Array(String))
    @gradle_artifacts ||= begin
      index = Hash(String, Array(String)).new
      build_modules.each do |dir|
        (index[File.basename(dir)] ||= [] of String) << dir
        {"settings.gradle", "settings.gradle.kts"}.each do |name|
          existing_file(File.join(dir, name)).try(&.match(GRADLE_ROOT_PROJECT_NAME)).try { |match| (index[match[1]] ||= [] of String) << dir }
        end
      end
      maven_modules.each { |artifact, dirs| (index[artifact] ||= [] of String).concat(dirs) }
      index.each_value(&.uniq!)
      index
    end
  end

  private def existing_file(path : String) : String?
    read_file(path) if File.exists?(path)
  end

  # `:common-security:api` and the accessor `commonSecurity.api` both
  # normalize to `commonsecurity:api`.
  private def normalize_gradle_path(path : String) : String
    path.split(':').reject(&.empty?).map(&.downcase.delete("-_")).join(':')
  end

  # ---- request matchers ---------------------------------------------------

  # Authorization rule matchers: servlet `requestMatchers(...)` and the
  # WebFlux `pathMatchers(...)`.
  MATCHERS_CALL = /\.\s*(antMatchers|requestMatchers|mvcMatchers|pathMatchers)\s*\(/

  # A chain is "scoped" when restricted by `securityMatcher(...)`,
  # `securityMatchers(m -> m.requestMatchers(...))` or Spring 5's
  # `http.antMatcher(...)`. The plural `antMatchers(...)` / `requestMatchers(...)`
  # forms are authorization *rules*, and `antMatcher(...)` as a static
  # factory (`requestMatchers(antMatcher("/h2/**"))`,
  # `AntPathRequestMatcher.antMatcher(X)`) builds a rule's matcher — only the
  # HttpSecurity method (`.antMatcher(` on anything but the factory class)
  # scopes the chain.
  SCOPE_MATCHER_CALL = /\b(securityMatchers?)\s*\(|(?<!AntPathRequestMatcher)\.\s*(antMatcher)\s*\(/

  # Calls that build a request matcher from their (pattern) arguments, so
  # `requestMatchers(antMatcher(X))` reads X. Regex matchers are not ant
  # patterns and are deliberately absent.
  MATCHER_FACTORY_CALL = /\A(?:new\s+)?(?:[\w$]+\s*(?:\([^()]*\))?\s*\.\s*)*(?:antMatcher|AntPathRequestMatcher|MvcRequestMatcher|matcher|pattern)\s*\((.*)\)\z/m
  # The servlet path (`MvcRequestMatcher.Builder`) or base path
  # (`PathPatternRequestMatcher.Builder`) in a factory's receiver chain, and
  # a builder variable that carries one
  # (`Builder mvc = new MvcRequestMatcher.Builder(i).servletPath("/ws")`).
  SERVLET_PATH_CALL    = /\.\s*(?:servletPath|basePath)\s*\(([^()]*)\)/
  SERVLET_PATH_BUILDER = /\b([A-Za-z_$][\w$]*)\s*=\s*[^;=]*?\.\s*(?:servletPath|basePath)\s*\(([^()]*)\)/
  RECEIVER_VARIABLE    = /\A\s*([A-Za-z_$][\w$]*)\s*\./
  NO_BUILDERS          = Hash(String, String?).new
  INLINE_STRING_ARRAY  = /\A(?:new\s+String\s*\[\s*\]\s*)?\{(.*)\}\z/m
  JAVA_STRING_LITERAL  = /\A"((?:[^"\\]|\\.)*)"\z/
  CONSTANT_REFERENCE   = /\A[A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*\z/
  QUALIFIED_CONSTANT   = /\b([A-Z][\w$]*)\.[A-Z_][A-Z0-9_$]*\b/

  CONFIG_LIST_GETTER       = /\A(?:this\s*\.\s*)?([a-z_$][\w$]*)\s*\.\s*(?:get([A-Z][\w$]*)|([a-z][\w$]*))\s*\(\s*\)(?:\s*\.\s*stream\s*\(\s*\))?(?:\s*\.\s*toArray\s*\([^()]*\))?\z/
  CONFIGURATION_PROPERTIES = /@ConfigurationProperties\s*\(\s*(?:(?:prefix|value)\s*=\s*)?"([^"]*)"/

  # String and `String[]` constants the config can name: its own, plus the
  # ones of every project class it references as `Cls.NAME` or imports
  # statically, read from that class's `Cls.java`.
  private def security_constants(content : String) : {Hash(String, String), Hash(String, Array(String))}
    project = Noir::TreeSitterJavaRouteExtractor::ProjectConstants.new
    project_arrays = Hash(String, Array(String)).new
    referenced = Set(String).new
    content.scan(QUALIFIED_CONSTANT) { |match| referenced << match[1] }
    content.scan(Noir::TreeSitterJavaRouteExtractor::STATIC_IMPORT_NAME_RE) { |match| referenced << match[1].split('.').last }
    referenced.each do |class_name|
      CodeLocator.instance.files_by_basename("#{class_name}.java").each do |file|
        next unless other = read_file(file)
        next unless other.includes?("static") || other.includes?("interface")
        other_strings, other_arrays = Noir::TreeSitterJavaRouteExtractor.extract_string_and_array_constants(other)
        other_strings.each { |name, value| project[name] ||= value if name.includes?('.') }
        other_arrays.each { |name, value| project_arrays[name] ||= value if name.includes?('.') }
      end
    end

    strings, arrays = Noir::TreeSitterJavaRouteExtractor.extract_string_and_array_constants(content, project.empty? ? nil : project)
    project_arrays.each { |name, value| arrays[name] ||= value }
    content.scan(Noir::TreeSitterJavaRouteExtractor::STATIC_IMPORT_NAME_RE) do |match|
      owner, name = match[1], match[2]
      if name == "*"
        project_arrays.each do |key, value|
          next unless key.starts_with?("#{owner}.")
          bare = key[(owner.size + 1)..]
          arrays[bare] ||= value unless bare.includes?('.')
        end
      elsif value = project_arrays["#{owner}.#{name}"]?
        arrays[name] ||= value
      end
    end
    {strings, arrays}
  end

  # nil for a chain that serves every request; the scope's ant patterns
  # otherwise, empty when the chain is scoped by a matcher noir cannot read.
  private def chain_scope(block : String, strings : Hash(String, String), arrays : Hash(String, Array(String))) : Array(String)?
    scope : Array(String)? = nil
    builders = servlet_path_builders(block, strings, arrays)
    block.scan(SCOPE_MATCHER_CALL) do |match|
      scope ||= [] of String
      open = match.byte_end(0) - 1
      next unless close = Noir::JSLiteralScanner.find_matching_paren_at_byte(block, open)
      args = block.byte_slice(open + 1, close - open - 1)
      if match[1]? == "securityMatchers"
        # `securityMatchers(m -> m.requestMatchers("/a/**", "/b/**"))`.
        args.scan(MATCHERS_CALL) do |inner|
          inner_open = inner.byte_end(0) - 1
          next unless inner_close = Noir::JSLiteralScanner.find_matching_paren_at_byte(args, inner_open)
          scope.concat(matcher_patterns(args.byte_slice(inner_open + 1, inner_close - inner_open - 1), strings, arrays, builders: builders))
        end
      else
        scope.concat(matcher_patterns(args, strings, arrays, builders: builders))
      end
    end
    scope.try &.uniq
  end

  # Matcher builder variables of `block` => the servlet path they carry
  # (nil: one noir cannot read).
  private def servlet_path_builders(block : String, strings : Hash(String, String), arrays : Hash(String, Array(String))) : Hash(String, String?)
    builders = Hash(String, String?).new
    block.scan(SERVLET_PATH_BUILDER) { |match| builders[match[1]] = matcher_patterns(match[2], strings, arrays).first? }
    builders
  end

  # Ant patterns a matcher argument list names: string literals, String /
  # `String[]` constants, inline `new String[]{...}` arrays, and matcher
  # factories over those (`antMatcher(X)`, `new AntPathRequestMatcher(X)`).
  # Anything else (`EndpointRequest.toAnyEndpoint()`, a computed list) names
  # nothing noir can read and is skipped.
  #
  # With `java_source`, a loop variable (`for (String url : X)`,
  # `X.forEach(url -> ...)`) reads its iterable `X`, and an iterable that is
  # a `@ConfigurationProperties` list getter (`props.getUrls()`,
  # `props.getUrls().toArray(new String[0])`) adds that property's key to
  # `config_keys` instead of a pattern. `builders` are the block's
  # `servlet_path_builders`.
  private def matcher_patterns(args : String, strings : Hash(String, String), arrays : Hash(String, Array(String)), depth : Int32 = 0,
                               loops : Hash(String, String)? = nil, config_keys : Array(String)? = nil, java_source : String? = nil,
                               builders : Hash(String, String?) = NO_BUILDERS) : Array(String)
    patterns = [] of String
    return patterns if depth > 4

    Noir::TopLevelSplit.split(args, ',', Noir::TopLevelSplit::Rules.new).each do |part|
      if literal = part.match(JAVA_STRING_LITERAL)
        patterns << literal[1]
      elsif part.matches?(CONSTANT_REFERENCE)
        next if part.starts_with?("HttpMethod.")
        if values = arrays[part]?
          patterns.concat(values)
        elsif value = strings[part]?
          patterns << value
        elsif iterable = loops.try &.[part]?
          if values = arrays[iterable]?
            patterns.concat(values)
          elsif config_keys && java_source && (key = config_list_key(iterable, java_source))
            config_keys << key
          end
        end
      elsif config_keys && java_source && (key = config_list_key(part, java_source))
        config_keys << key
      elsif inner = part.match(INLINE_STRING_ARRAY)
        patterns.concat(matcher_patterns(inner[1], strings, arrays, depth + 1, builders: builders))
      elsif inner = part.match(MATCHER_FACTORY_CALL)
        found = matcher_patterns(inner[1], strings, arrays, depth + 1, builders: builders)
        # `mvc.servletPath("/ws").pattern("/**")` matches `/ws/**`; a
        # servlet path noir cannot read names nothing.
        receiver = part[0, inner.begin(1)]
        if call = receiver.match(SERVLET_PATH_CALL)
          next unless servlet_path = matcher_patterns(call[1], strings, arrays, depth + 1).first?
          patterns.concat(found.map { |pattern| Noir::URLPath.join_rooted(servlet_path, pattern) })
        elsif (variable = receiver.match(RECEIVER_VARIABLE)) && builders.has_key?(variable[1])
          next unless built = builders[variable[1]]
          patterns.concat(found.map { |pattern| Noir::URLPath.join_rooted(built, pattern) })
        else
          patterns.concat(found)
        end
      end
    end
    patterns
  end

  # `prefix.property` of the `@ConfigurationProperties` list that `expr`
  # (`ignoreUrls.getUrls()`) reads in `source`: the variable's declared type
  # is resolved through the file's import or package, and that class must
  # bind a prefix and declare the property as a String collection or array.
  private def config_list_key(expr : String, source : String) : String?
    return unless match = expr.match(CONFIG_LIST_GETTER)
    variable = match[1]
    property = match[2]?.try { |getter| getter[0].downcase + getter[1..] } || match[3]
    return unless declared = source.match(/\b([A-Z][\w$]*)(?:<[^<>]*>)?\s+#{Regex.escape(variable)}\s*[;=,)]/)
    return unless file = Analyzer::Java::JavaEngine.java_type_file(declared[1], source)
    return unless (props = read_file(file)) && (bound = props.match(CONFIGURATION_PROPERTIES))
    return unless props.matches?(/\b(?:List|Set|Collection|Iterable)\s*<\s*String\s*>\s+#{Regex.escape(property)}\b|\bString\s*\[\s*\]\s+#{Regex.escape(property)}\b/)
    prefix = bound[1].strip
    prefix.empty? ? property : "#{prefix}.#{property}"
  end

  # Spring's ant match of a request path: `*` one segment, `**` any depth,
  # none included (`/**/hook` matches `/hook`, `/assets/**` serves
  # `/assets`). A comma-separated pattern matches when any part does.
  private def matches_ant_pattern?(url : String, pattern : String) : Bool
    patterns = pattern.split(",").map(&.strip)
    normalized_url = normalize_security_path(url)

    patterns.any? do |p|
      p = normalize_security_path(p)
      next false if p.empty?

      normalized_url.matches?(ant_pattern_regex(p))
    end
  rescue ex
    @logger.debug "#{self.class.name}: Failed to match ant pattern '#{pattern}': #{ex.message}"
    false
  end

  private def normalize_security_path(path : String) : String
    value = path.strip
    return value if value.empty?
    value.starts_with?("/") ? value : "/#{value}"
  end

  # Every endpoint is matched against every recorded security rule, so this is
  # called O(endpoints x rules) times over a small set of distinct patterns.
  # Memoize so the same PCRE2 pattern isn't recompiled thousands of times.
  @ant_pattern_regexes = Hash(String, Regex).new

  private def ant_pattern_regex(pattern : String) : Regex
    @ant_pattern_regexes[pattern] ||= begin
      escaped = Regex.escape(pattern)
        .gsub("/\\*\\*/", "(?:/.*)?/")
        .sub(/\/\\\*\\\*\z/, "(?:/.*)?")
        .gsub("\\*\\*", ".*")
        .gsub("\\*", "[^/]*")

      /^#{escaped}\/?$/
    end
  end
end
