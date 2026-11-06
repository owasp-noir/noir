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
          source.file.routes.each_with_index do |route, index|
            prefixes.for_route(source, index).each do |prefix, guard|
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
    # no call places the function; a function with no call seen, or one on
    # a call cycle, keeps the URL its own routes spell, unguarded. Functions
    # are matched by name; when one name is declared in several Gradle
    # modules, call sites in the function's own module win, so two services
    # that each mount their own `fun Route.api()` keep apart.
    # ponytail: two same-named functions in one module share call sites.
    class MountPrefixes
      # Past this many placements for one function, keep its own URL.
      MAX_PREFIXES = 1024

      alias Extractor = Noir::TreeSitterKotlinKtorRouteExtractor
      # A prefix and the authenticate block it is mounted behind, if any.
      alias Placement = {String, String?}
      # A function as resolved: its name and the module it is read from.
      alias Node = {String, String}

      record Source, path : String, module_root : String, file : Extractor::FileRoutes
      record Site, prefix : String?, caller : String?, guard : String?, module_root : String

      ROOT = [{"", nil}] of Placement

      @sites = Hash(String, Array(Site)).new
      @memo = Hash(Node, Array(Placement)).new
      @modules = Hash(String, Set(String)).new
      @route_functions = Hash(Extractor::FileRoutes, Array(String?)).new
      @cyclic = Set(Node).new

      def initialize(sources : Array(Source))
        sources.each do |source|
          source.file.functions.each { |function| (@modules[function.name] ||= Set(String).new) << source.module_root }
        end
        sources.each do |source|
          file = source.file
          @route_functions[file] = MountPrefixes.innermost(function_spans(file), file.routes.map(&.byte))
          next if file.mounts.empty?
          points = file.mounts.map(&.byte)
          callers = MountPrefixes.innermost(function_spans(file), points)
          guards = MountPrefixes.innermost(file.auth_blocks.map { |block| {block.start_byte, block.end_byte, block.description} }, points)
          file.mounts.each_with_index do |mount, index|
            next unless @modules.has_key?(mount.name)
            (@sites[mount.name] ||= [] of Site) << Site.new(mount.prefix, callers[index], guards[index], source.module_root)
          end
        end
        mark_cycles
      end

      # Placements for the `index`th route of `source`; the bare URL outside
      # any `Route.` function.
      def for_route(source : Source, index : Int32) : Array(Placement)
        return ROOT unless name = @route_functions[source.file][index]?
        resolve({name, source.module_root})
      end

      private def function_spans(file : Extractor::FileRoutes) : Array({Int32, Int32, String})
        file.functions.map { |function| {function.start_byte, function.end_byte, function.name} }
      end

      # The innermost span (start inclusive, end exclusive) holding each
      # point, for spans that nest, in one sweep over both sorted lists.
      def self.innermost(spans : Array({Int32, Int32, String}), points : Array(Int32)) : Array(String?)
        result = Array(String?).new(points.size, nil)
        return result if spans.empty?
        sorted = spans.sort_by { |span| {span[0], -span[1]} }
        stack = [] of {Int32, Int32, String}
        next_span = 0
        (0...points.size).to_a.sort_by! { |index| points[index] }.each do |index|
          point = points[index]
          while next_span < sorted.size && sorted[next_span][0] <= point
            span = sorted[next_span]
            while (top = stack.last?) && top[1] <= span[0]
              stack.pop
            end
            stack << span
            next_span += 1
          end
          while (top = stack.last?) && top[1] <= point
            stack.pop
          end
          result[index] = stack.last?.try(&.[2])
        end
        result
      end

      # The call sites that place `node`, after the module and
      # placed-over-unplaced narrowing.
      private def sites_for(node : Node) : Array(Site)
        name, module_root = node
        sites = @sites[name]? || [] of Site
        if @modules[name].size > 1
          local = sites.select { |site| site.module_root == module_root }
          sites = local unless local.empty?
        end
        placed = sites.reject { |site| site.prefix.nil? }
        placed.empty? ? sites : placed
      end

      private def caller_node(site : Site) : Node?
        site.caller.try { |caller| {caller, site.module_root} }
      end

      # Tarjan's strongly connected components over caller edges, once: a
      # function on a cycle (a component of several, or one calling itself)
      # keeps its own URL, so `resolve` below walks a DAG and memoises it all.
      # ponytail: recursive; a call chain deeper than the fiber stack would overflow.
      private def mark_cycles
        @modules.each do |name, roots|
          roots.each do |root|
            node = {name, root}
            tarjan(node) unless @tarjan_index.has_key?(node)
          end
        end
      end

      @tarjan_index = Hash(Node, Int32).new
      @tarjan_low = Hash(Node, Int32).new
      @tarjan_stack = [] of Node
      @tarjan_on_stack = Set(Node).new

      private def tarjan(node : Node) : Nil
        @tarjan_index[node] = @tarjan_low[node] = @tarjan_index.size
        @tarjan_stack << node
        @tarjan_on_stack << node
        sites_for(node).each do |site|
          next unless caller = caller_node(site)
          if !@tarjan_index.has_key?(caller)
            tarjan(caller)
            @tarjan_low[node] = {@tarjan_low[node], @tarjan_low[caller]}.min
          elsif @tarjan_on_stack.includes?(caller)
            @tarjan_low[node] = {@tarjan_low[node], @tarjan_index[caller]}.min
          end
        end
        return unless @tarjan_low[node] == @tarjan_index[node]

        component = [] of Node
        loop do
          member = @tarjan_stack.pop
          @tarjan_on_stack.delete(member)
          component << member
          break if member == node
        end
        self_call = sites_for(node).any? { |site| caller_node(site) == node }
        @cyclic.concat(component) if component.size > 1 || self_call
      end

      private def resolve(node : Node) : Array(Placement)
        if cached = @memo[node]?
          return cached
        end
        return @memo[node] = ROOT if @cyclic.includes?(node)
        sites = sites_for(node)
        return @memo[node] = ROOT if sites.empty?

        found = [] of Placement
        sites.each do |site|
          unless prefix = site.prefix
            found << {"", nil}
            next
          end
          outer = (caller = caller_node(site)) ? resolve(caller) : ROOT
          outer.each { |head, guard| found << {join(head, prefix), guard || site.guard} }
        end
        @memo[node] = merge(found)
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
