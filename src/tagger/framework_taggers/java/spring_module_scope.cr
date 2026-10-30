require "../../../models/framework_tagger"
require "../../../utils/c_comments"

# Which build units' Spring beans serve an endpoint. A `SecurityFilterChain`,
# a `csrf` setting or a CORS mapping lives in one Maven / Gradle module and
# applies only to the apps whose runtime classpath holds that module, so
# `spring_auth` and `spring_security` judge an endpoint once per app that
# serves it (`per_serving_classpath`).
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
  # when there are any. Nil when `module_dir`'s classpath is unknown.
  private def serving_apps(module_dir : String) : Array(String)?
    return @serving_apps[module_dir] if @serving_apps.has_key?(module_dir)
    @serving_apps[module_dir] = if module_classpath(module_dir)
                                  hosts = build_modules.select do |dir|
                                    module_classpath(dir).try(&.[0].includes?(module_dir))
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
  # included), whether Spring Security is on it}`; nil when unknown.
  private def module_classpath(module_dir : String) : {Set(String), Bool}?
    return @module_classpaths[module_dir] if @module_classpaths.has_key?(module_dir)
    @module_classpaths[module_dir] = if File.exists?(File.join(module_dir, "pom.xml"))
                                       maven_classpath(module_dir)
                                     else
                                       gradle_classpath(module_dir)
                                     end
  end

  # By Maven's rules: a parent's dependencies are the module's own; a
  # dependency's own dependencies come along unless `optional`; `test`
  # scope never reaches the runtime.
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
        maven_modules[dependency[:artifact]]?.try(&.each { |dependency_dir| queue << {dependency_dir, false} })
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
  # `project(":x").projectDir = file("libs/x")` (or `File(rootDir, "libs/x")`).
  GRADLE_PROJECT_DIR       = /\bproject\s*\(\s*["']([^"']+)["']\s*\)\s*\.\s*projectDir\s*=\s*(?:file\s*\(|(?:new\s+)?File\s*\(\s*\w+\s*,)\s*["']([^"']+)["']/
  GRADLE_ROOT_PROJECT_NAME = /\brootProject\.name\s*=\s*["']([^"']+)["']/
  GRADLE_CONFIGURATION     = /\A\s*([A-Za-z_]\w*)/
  GRADLE_SCRIPT_EXTENSION  = /\.gradle(?:\.kts)?\z/

  @gradle_projects = Hash(String, Hash(String, String)?).new

  # By Gradle's rules: the module and, transitively, the `project(...)`
  # dependencies of its build file outside test configurations. Separate
  # builds (no shared `settings.gradle`) share nothing but coordinate
  # dependencies on each other. Every module of the build when something
  # else can add a project dependency (a root build file naming
  # `project(...)`, as `subprojects {}` does, or a script or convention
  # plugin naming one) or a reference does not resolve; nil when that
  # build's root is outside the scan.
  #
  # ponytail: Spring Security on a Gradle classpath is not read, so Boot's
  # default chain is never assumed for a Gradle app; read the
  # `spring-boot-starter-security` coordinates when that matters.
  private def gradle_classpath(module_dir : String) : {Set(String), Bool}?
    root = gradle_root(module_dir)
    projects = root ? gradle_projects(root) : nil
    return gradle_build(module_dir) if root && projects.nil?

    dirs = Set(String).new
    queue = [module_dir]
    while dir = queue.shift?
      next unless dirs.add?(dir)
      next unless refs = gradle_dependencies(dir)
      refs.each do |ref, project|
        if project
          return gradle_build(module_dir) unless target = projects.try &.[ref]?
          queue << target
        else
          # Another build's module: its whole build (or Maven classpath)
          # comes along, read no further.
          gradle_artifacts[ref]?.try &.each do |target|
            return unless found = File.exists?(File.join(target, "pom.xml")) ? maven_classpath(target) : gradle_build(target)
            dirs.concat(found[0])
          end
        end
      end
    end
    {dirs, false}
  end

  private def gradle_root(module_dir : String) : String?
    nearest_project_root(File.join(module_dir, "build.gradle"), GRADLE_SETTINGS)
  end

  # Every module of the Gradle build holding `module_dir`; nil when that
  # build's root (its `settings.gradle`) is outside the scan.
  private def gradle_build(module_dir : String) : {Set(String), Bool}?
    return unless root = gradle_root(module_dir)
    {Set.new(build_modules.select { |dir| Noir::PathScope.under_root?(dir, root) }), false}
  end

  # Normalized project path (`a:b`) => directory, for the build rooted at
  # `root`; nil when something besides its modules' own build files can add
  # project dependencies.
  private def gradle_projects(root : String) : Hash(String, String)?
    return @gradle_projects[root] if @gradle_projects.has_key?(root)
    @gradle_projects[root] = begin
      opaque = {"build.gradle", "build.gradle.kts"}.any? { |name| read_gradle_script(File.join(root, name)).try(&.matches?(GRADLE_PROJECT_MENTION)) } ||
               gradle_injecting_scripts.any?(&.starts_with?("#{root}/"))
      unless opaque
        index = {"" => root}
        build_modules.each do |dir|
          next unless dir.starts_with?("#{root}/")
          index[normalize_gradle_path(dir[(root.size + 1)..].tr("/", ":"))] = dir
        end
        {"settings.gradle", "settings.gradle.kts"}.each do |name|
          read_gradle_script(File.join(root, name)).try &.scan(GRADLE_PROJECT_DIR) { |match| index[normalize_gradle_path(match[1])] = File.expand_path(match[2], root) }
        end
        index
      end
    end
  end

  @gradle_injecting_scripts : Array(String)? = nil

  # Gradle scripts that are neither a build nor a settings file (`apply
  # from:` scripts, `buildSrc` / `build-logic` convention plugins) and name
  # a `project(...)`.
  private def gradle_injecting_scripts : Array(String)
    @gradle_injecting_scripts ||= {".gradle", ".kts"}.flat_map do |ext|
      collect_files_by_extension(ext).compact_map do |file|
        base = File.basename(file)
        next if !base.matches?(GRADLE_SCRIPT_EXTENSION) || base.matches?(BUILD_FILE) || base.matches?(GRADLE_SETTINGS)
        path = Noir::PathScope.expand(file)
        path if read_gradle_script(path).try(&.matches?(GRADLE_PROJECT_MENTION))
      end
    end
  end

  @gradle_dependencies = Hash(String, Array({String, Bool})?).new

  # The `{project path or coordinate name, is project}` dependencies of the
  # module's build file; nil when it has none.
  private def gradle_dependencies(dir : String) : Array({String, Bool})?
    return @gradle_dependencies[dir] if @gradle_dependencies.has_key?(dir)
    @gradle_dependencies[dir] = begin
      content = read_gradle_script(File.join(dir, "build.gradle")) || read_gradle_script(File.join(dir, "build.gradle.kts"))
      content.try do |code|
        refs = [] of {String, Bool}
        code.each_line do |line|
          next if line.match(GRADLE_CONFIGURATION).try(&.[1].downcase.includes?("test"))
          read = refs.size
          line.scan(GRADLE_PROJECT_REF) { |match| refs << {normalize_gradle_path(match[1]), true} }
          line.scan(GRADLE_PROJECT_ACCESSOR) { |match| refs << {normalize_gradle_path(match[1].tr(".", ":")), true} }
          # A project dependency noir cannot read resolves to nothing.
          refs << {"?", true} if refs.size == read && line.matches?(GRADLE_PROJECT_MENTION)
          line.scan(GRADLE_COORDINATE) { |match| refs << {match[1], false} }
        end
        refs
      end
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
          read_gradle_script(File.join(dir, name)).try(&.match(GRADLE_ROOT_PROJECT_NAME)).try { |match| (index[match[1]] ||= [] of String) << dir }
        end
      end
      maven_modules.each { |artifact, dirs| (index[artifact] ||= [] of String).concat(dirs) }
      index
    end
  end

  private def read_gradle_script(path : String) : String?
    return unless File.exists?(path) && (content = read_file(path))
    Noir::CComments.strip(content)
  end

  # `:common-security:api` and the accessor `commonSecurity.api` both
  # normalize to `commonsecurity:api`.
  private def normalize_gradle_path(path : String) : String
    path.split(':').reject(&.empty?).map(&.downcase.delete("-_")).join(':')
  end

  # Spring's ant match of a request path: `*` one segment, `**` any depth,
  # and a trailing `/**` also matches the bare prefix (`/assets/**` serves
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
        .sub(/\/\\\*\\\*\z/, "(?:/.*)?")
        .gsub("\\*\\*", ".*")
        .gsub("\\*", "[^/]*")

      /^#{escaped}\/?$/
    end
  end
end
