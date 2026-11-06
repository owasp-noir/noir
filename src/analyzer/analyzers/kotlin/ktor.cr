require "../../../models/analyzer"
require "../../../miniparsers/kotlin_ktor_route_extractor_ts"
require "../../engines/kotlin_engine"

module Analyzer::Kotlin
  class Ktor < Analyzer
    analyzer_for "kotlin_ktor"

    KOTLIN_EXTENSION = "kt"

    def analyze
      include_callee = callees_needed?
      file_list = all_files()
      kotlin_files = file_list.select do |path|
        path.ends_with?(".#{KOTLIN_EXTENSION}") &&
          File.exists?(path) &&
          !KotlinEngine.test_path?(base_relative_path(path))
      end
      file_contents = Hash(String, String).new
      string_constants_by_base = Hash(String, Hash(String, String)).new do |hash, key|
        hash[key] = Hash(String, String).new
      end
      raw_resources_by_base = Hash(String, Array(Noir::TreeSitterKotlinKtorRouteExtractor::RawResource)).new do |hash, key|
        hash[key] = [] of Noir::TreeSitterKotlinKtorRouteExtractor::RawResource
      end
      kotlin_files.each do |path|
        base = configured_base_for(path)
        string_constants = string_constants_by_base[base]
        content = file_contents[path] = read_file_content(path)
        Noir::TreeSitterKotlinKtorRouteExtractor.extract_string_constants(content).each do |name, value|
          next unless fully_qualified_constant?(name)

          string_constants[name] ||= value
        end

        # `@Resource` classes may live in a shared module separate from
        # the route files (Ktor KMP `commonMain`), so collect them across
        # the whole configured base before composing type-safe-route paths.
        if content.includes?("@Resource")
          raw_resources_by_base[base].concat(Noir::TreeSitterKotlinKtorRouteExtractor.extract_resource_classes(content))
        end
      end

      resource_paths_by_base = Hash(String, Hash(String, Noir::TreeSitterKotlinKtorRouteExtractor::ResolvedResource)).new
      raw_resources_by_base.each do |base, raw_resources|
        resource_paths_by_base[base] = Noir::TreeSitterKotlinKtorRouteExtractor.compose_resources(raw_resources)
      end

      parsed_by_base = Hash(String, Array(MountPrefixes::Source)).new do |hash, key|
        hash[key] = [] of MountPrefixes::Source
      end
      kotlin_files.each do |path|
        content = file_contents[path]
        next unless potential_ktor_route_file?(content)

        base = configured_base_for(path)
        string_constants = string_constants_by_base[base]? || Hash(String, String).new
        resource_paths = resource_paths_by_base[base]? || Hash(String, Noir::TreeSitterKotlinKtorRouteExtractor::ResolvedResource).new
        module_root = Noir::PathScope.marker_root(path, base, {"/src/main/kotlin/", "/src/"}) || File.dirname(path)
        parsed_by_base[base] << MountPrefixes::Source.new(path, module_root,
          Noir::TreeSitterKotlinKtorRouteExtractor.extract_file_routes(content, string_constants, resource_paths, include_callees: include_callee))
      end

      parsed_by_base.each_value do |files|
        prefixes = MountPrefixes.new(files)
        files.each do |source|
          source.file.routes.each do |route|
            prefixes.for_line(source, route.line).each do |prefix, guard|
              endpoint = build_endpoint(mounted(route, prefix), source.path)
              endpoint.add_tag(Tag.new("auth", "Protected by #{guard}", "ktor_auth")) if guard
              @result << endpoint
            end
          end
        end
      end

      Fiber.yield
      @result
    end

    # One precompiled `Regex.union` scan (PCRE2 JIT, auto-escapes each
    # literal) replaces the three OR-ed `String#includes?` passes over the
    # same buffer — this gate runs once per Kotlin file in the scan.
    POTENTIAL_KTOR_ROUTE_RE = Regex.union("routing", "io.ktor.server.routing", "Route.")

    private def potential_ktor_route_file?(content : String) : Bool
      content.matches?(POTENTIAL_KTOR_ROUTE_RE)
    end

    # A route declared in `fun Route.userRoutes()` lives under every prefix
    # the function is called at: `route("/{year}") { yearBasedRoutes() }`,
    # with `yearBasedRoutes` in turn calling `userRoutes()`, serves
    # `/{year}/sign`, not `/sign`. A call inside a non-optional
    # `authenticate { }` block puts what it mounts behind that block. A
    # function with no call seen, or with a call that cannot be placed
    # (`someRoute.userRoutes()`, a call outside routing code), keeps the URL
    # its own routes spell, unguarded. Functions are matched by name: call
    # sites in the function's own Gradle module win, so two services that
    # each mount their own `fun Route.api()` keep apart; a function called
    # only from other modules takes those modules' call sites.
    # ponytail: two same-named functions in one module share call sites.
    class MountPrefixes
      MAX_PREFIXES = 16

      alias Extractor = Noir::TreeSitterKotlinKtorRouteExtractor
      # A prefix and the authenticate block it is mounted behind, if any.
      alias Placement = {String, String?}

      record Source, path : String, module_root : String, file : Extractor::FileRoutes
      record Site, prefix : String?, caller : String?, guard : String?, module_root : String

      ROOT = [{"", nil}] of Placement

      @sites = Hash(String, Array(Site)).new
      @memo = Hash({String, String}, Array(Placement)).new

      def initialize(sources : Array(Source))
        declared = Set(String).new
        sources.each { |source| source.file.functions.each { |function| declared << function.name } }
        sources.each do |source|
          file = source.file
          file.mounts.each do |mount|
            next unless declared.includes?(mount.name)
            guard = file.auth_blocks.find { |block| block.start_line <= mount.line && mount.line <= block.end_line }.try(&.description)
            (@sites[mount.name] ||= [] of Site) << Site.new(mount.prefix, enclosing(file, mount.line), guard, source.module_root)
          end
        end
      end

      # Placements for a route declared on `line` of `source`; the bare URL
      # outside any `Route.` function.
      def for_line(source : Source, line : Int32) : Array(Placement)
        name = enclosing(source.file, line)
        name ? resolve(name, source.module_root, Set({String, String}).new) : ROOT
      end

      private def enclosing(file : Extractor::FileRoutes, line : Int32) : String?
        file.functions.select { |function| function.start_line <= line && line <= function.end_line }
          .min_by? { |function| function.end_line - function.start_line }.try(&.name)
      end

      private def resolve(name : String, module_root : String, visiting : Set({String, String})) : Array(Placement)
        key = {name, module_root}
        if cached = @memo[key]?
          return cached
        end
        sites = @sites[name]?
        return ROOT if sites.nil? || visiting.includes?(key)

        local = sites.select { |site| site.module_root == module_root }
        sites = local unless local.empty?
        visiting << key
        found = [] of Placement
        sites.each do |site|
          unless prefix = site.prefix
            found << {"", nil}
            next
          end
          outer = (caller = site.caller) ? resolve(caller, site.module_root, visiting) : ROOT
          outer.each { |head, guard| found << {join(head, prefix), guard || site.guard} }
        end
        visiting.delete(key)
        @memo[key] = merge(found)
      end

      # One placement per prefix; served open by any call site, it is open.
      private def merge(found : Array(Placement)) : Array(Placement)
        merged = Hash(String, String?).new
        found.each do |prefix, guard|
          merged[prefix] = merged.has_key?(prefix) ? (merged[prefix] && guard) : guard
        end
        merged.to_a.first(MAX_PREFIXES)
      end

      def self.join(head : String, tail : String) : String
        return tail if head.empty?
        return head if tail.empty? || tail == "/"
        Extractor.route_scope_join(head, tail)
      end

      private def join(head : String, tail : String) : String
        self.class.join(head, tail)
      end
    end

    private def mounted(route : Noir::TreeSitterKotlinKtorRouteExtractor::Route, prefix : String) : Noir::TreeSitterKotlinKtorRouteExtractor::Route
      prefix.empty? ? route : route.with_path(MountPrefixes.join(prefix, route.path))
    end

    private def fully_qualified_constant?(name : String) : Bool
      name.count('.') >= 2
    end

    # The parameter name inside one Ktor placeholder. Ktor spells the
    # tailcard as `{name...}` and the optional as `{name?}`, but the
    # handler still reads `call.parameters["name"]` — the decoration
    # describes the segment, not the parameter. Emitting the raw body
    # produced params literally named `segments...` and `name?`, which
    # no probe or spec fill could ever match. `{...}` is the anonymous
    # tailcard and names nothing.
    private def ktor_path_param_name(body : String) : String?
      name = body.rchop("...").rchop("?")
      name.empty? ? nil : name
    end

    private def build_endpoint(route : Noir::TreeSitterKotlinKtorRouteExtractor::Route, path : String) : Endpoint
      details = Details.new(PathInfo.new(path, route.line + 1))
      params = [] of Param
      path_param_names = Set(String).new

      # Path placeholders (`{id}`) — emit one path-typed param per
      # placeholder. The optimizer also synthesises these from the
      # URL string, but emitting here keeps parity with the legacy
      # analyzer.
      route.path.scan(/\{([^}]+)\}/) do |match|
        name = ktor_path_param_name(match[1])
        next unless name
        path_param_names << name
        params << Param.new(name, "", "path")
      end

      if rt = route.receive_type
        params << Param.new("body", rt, "json")
      elsif route.has_body?
        params << Param.new("body", "", "json")
      end

      route.query_params.each do |name|
        next if path_param_names.includes?(name)
        params << Param.new(name, "", "query")
      end

      route.header_params.each do |name|
        params << Param.new(name, "", "header")
      end

      route.form_params.each do |name|
        params << Param.new(name, "", "form")
      end

      endpoint = Endpoint.new(route.path, route.verb, params, details)

      # 1-hop callees out of the handler lambda body. The Route
      # extractor doesn't know the file path it came from, so attach
      # it here.
      route.callees.each do |entry|
        name, line = entry
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end

      endpoint
    end
  end
end
