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
    # `authenticate { }` block puts what it mounts behind that block. A call
    # whose prefix is unknown (`this@routing.userRoutes()`) counts only when
    # no call places the function; a function with no call seen keeps the
    # URL its own routes spell, unguarded. Functions are matched by name;
    # when one name is declared in several Gradle modules, call sites in the
    # function's own module win, so two services that each mount their own
    # `fun Route.api()` keep apart.
    # ponytail: two same-named functions in one module share call sites.
    class MountPrefixes
      # Past this many placements for one function, keep its own URL.
      MAX_PREFIXES = 1024

      alias Extractor = Noir::TreeSitterKotlinKtorRouteExtractor
      # A prefix and the authenticate block it is mounted behind, if any.
      alias Placement = {String, String?}

      record Source, path : String, module_root : String, file : Extractor::FileRoutes
      record Site, prefix : String?, caller : String?, guard : String?, module_root : String

      ROOT = [{"", nil}] of Placement

      @sites = Hash(String, Array(Site)).new
      @memo = Hash({String, String}, Array(Placement)).new
      @modules = Hash(String, Set(String)).new
      @cycle_hit = false

      @functions_by_line = Hash(Extractor::FileRoutes, Array(String?)).new

      def initialize(sources : Array(Source))
        sources.each do |source|
          source.file.functions.each { |function| (@modules[function.name] ||= Set(String).new) << source.module_root }
        end
        sources.each do |source|
          file = source.file
          next if file.mounts.empty?
          guards = MountPrefixes.innermost(file.auth_blocks.map { |block| {block.start_line, block.end_line, block.description} })
          file.mounts.each do |mount|
            next unless @modules.has_key?(mount.name)
            (@sites[mount.name] ||= [] of Site) << Site.new(mount.prefix, enclosing(file, mount.line), guards[mount.line]?, source.module_root)
          end
        end
      end

      # The innermost span covering each line, for spans that nest (function
      # and block bodies do), in one sweep: lookups stay O(1) on a file with
      # thousands of route functions.
      def self.innermost(spans : Array({Int32, Int32, String})) : Array(String?)
        return [] of String? if spans.empty?
        last = spans.max_of(&.[1])
        table = Array(String?).new(last + 1, nil)
        sorted = spans.sort_by { |span| {span[0], -span[1]} }
        stack = [] of {Int32, Int32, String}
        next_span = 0
        (0..last).each do |line|
          while next_span < sorted.size && sorted[next_span][0] <= line
            stack << sorted[next_span]
            next_span += 1
          end
          while (top = stack.last?) && top[1] < line
            stack.pop
          end
          table[line] = stack.last?.try(&.[2])
        end
        table
      end

      # Placements for a route declared on `line` of `source`; the bare URL
      # outside any `Route.` function.
      def for_line(source : Source, line : Int32) : Array(Placement)
        return ROOT unless name = enclosing(source.file, line)
        placements = resolve(name, source.module_root, Set({String, String}).new)
        placements.empty? ? ROOT : placements
      end

      private def enclosing(file : Extractor::FileRoutes, line : Int32) : String?
        @functions_by_line[file] ||= MountPrefixes.innermost(file.functions.map { |function| {function.start_line, function.end_line, function.name} })
        @functions_by_line[file][line]?
      end

      # Empty when every call reaches this function only through a cycle
      # back into the caller being resolved.
      private def resolve(name : String, module_root : String, visiting : Set({String, String})) : Array(Placement)
        key = {name, module_root}
        if cached = @memo[key]?
          return cached
        end
        if visiting.includes?(key)
          @cycle_hit = true
          return [] of Placement
        end
        return ROOT unless sites = @sites[name]?

        if @modules[name].size > 1
          local = sites.select { |site| site.module_root == module_root }
          sites = local unless local.empty?
        end
        placed = sites.reject { |site| site.prefix.nil? }
        sites = placed unless placed.empty?

        outer_hit = @cycle_hit
        @cycle_hit = false
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
        result = merge(found)
        # A result that met a cycle is partial: it is right for this call
        # chain but not for one entering the cycle elsewhere.
        @memo[key] = result unless @cycle_hit
        @cycle_hit ||= outer_hit
        result
      end

      # One placement per prefix; served open by any call site, it is open.
      private def merge(found : Array(Placement)) : Array(Placement)
        merged = Hash(String, String?).new
        found.each do |prefix, guard|
          merged[prefix] = merged.has_key?(prefix) ? (merged[prefix] && guard) : guard
        end
        merged.size > MAX_PREFIXES ? ROOT : merged.to_a
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
