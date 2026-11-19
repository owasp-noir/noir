require "../../../models/analyzer"
require "../../../miniparsers/http4k_extractor_ts"
require "../../engines/kotlin_engine"

module Analyzer::Kotlin
  class Http4k < Analyzer
    analyzer_for "kotlin_http4k"

    KOTLIN_EXTENSION = "kt"
    HTTP4K_MARKER    = "org.http4k"

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
      contract_routes_by_base = Hash(String, Hash(String, Array(Noir::TreeSitterHttp4kExtractor::Route))).new do |hash, key|
        hash[key] = Hash(String, Array(Noir::TreeSitterHttp4kExtractor::Route)).new
      end
      kotlin_files.each do |path|
        string_constants = string_constants_by_base[configured_base_for(path)]
        content = file_contents[path] = read_file_content(path)
        Noir::TreeSitterHttp4kExtractor.extract_string_constants(content).each do |name, value|
          next unless fully_qualified_constant?(name)

          string_constants[name] ||= value
        end
      end

      kotlin_files.each do |path|
        content = file_contents[path]
        next unless content.includes?("bindContract")

        base = configured_base_for(path)
        string_constants = string_constants_by_base[base]? || Hash(String, String).new
        Noir::TreeSitterHttp4kExtractor.extract_contract_route_functions(content, string_constants, include_callees: include_callee).each do |name, routes|
          contract_routes_by_base[base][name] ||= [] of Noir::TreeSitterHttp4kExtractor::Route
          contract_routes_by_base[base][name].concat(routes)
        end
      end

      routes_by_base = Hash(String, Array({Noir::TreeSitterHttp4kExtractor::Route, String})).new do |hash, key|
        hash[key] = [] of {Noir::TreeSitterHttp4kExtractor::Route, String}
      end
      mounts_by_base = Hash(String, Array(Noir::TreeSitterHttp4kExtractor::Mount)).new do |hash, key|
        hash[key] = [] of Noir::TreeSitterHttp4kExtractor::Mount
      end
      kotlin_files.each do |path|
        content = file_contents[path]
        next unless content.includes?(HTTP4K_MARKER)

        base = configured_base_for(path)
        string_constants = string_constants_by_base[base]? || Hash(String, String).new
        contract_routes = contract_routes_by_base[base]? || Hash(String, Array(Noir::TreeSitterHttp4kExtractor::Route)).new
        Noir::TreeSitterHttp4kExtractor.extract_routes(
          content, string_constants, include_callees: include_callee, contract_routes: contract_routes, mounts: mounts_by_base[base]
        ).each do |route|
          routes_by_base[base] << {route, path}
        end
      end

      routes_by_base.each do |base, routes|
        sites = mounts_by_base[base].group_by(&.name)
        memo = Hash(String, Array(String)).new
        routes.each do |route, path|
          prefixes = route.owner.try { |owner| mount_prefixes(owner, sites, memo, Set(String).new, 0) } || [""]
          prefixes.each do |prefix|
            @result << build_endpoint(prefix.empty? ? route : route.with_path(mounted_path(prefix, route.path)), path)
          end
        end
      end

      Fiber.yield
      @result
    end

    MAX_MOUNT_DEPTH    =   64
    MAX_MOUNT_PREFIXES = 1024

    # Every prefix the router declared as `name` is served under: one per
    # `"/p" bind name` site, under the prefixes of the router holding that
    # site. Unmounted, on a cycle or past the caps, it keeps its own URLs.
    # ponytail: mounts match declarations by name across the base; scope by
    # file or import if same-named routers collide.
    private def mount_prefixes(name : String,
                               sites : Hash(String, Array(Noir::TreeSitterHttp4kExtractor::Mount)),
                               memo : Hash(String, Array(String)),
                               visiting : Set(String),
                               depth : Int32) : Array(String)
      if cached = memo[name]?
        return cached
      end
      root = [""]
      found = sites[name]?
      return root unless found && depth < MAX_MOUNT_DEPTH && visiting.add?(name)
      prefixes = found.flat_map do |site|
        outer = site.owner.try { |owner| mount_prefixes(owner, sites, memo, visiting, depth + 1) } || root
        outer.map { |head| head.empty? ? site.prefix : Noir::URLPath.join_trimmed(head, site.prefix) }
      end.uniq!
      visiting.delete(name)
      memo[name] = prefixes.size > MAX_MOUNT_PREFIXES ? root : prefixes
    end

    # `"/users" bind userRoutes` with `"/" bind GET` inside serves `/users`.
    private def mounted_path(prefix : String, path : String) : String
      path == "/" ? prefix : Noir::URLPath.join_trimmed(prefix, path)
    end

    # `Paths.API` or `com.example.Paths.API`; a bare name collides
    # across files too often to share.
    private def fully_qualified_constant?(name : String) : Bool
      name.includes?('.')
    end

    private def build_endpoint(route : Noir::TreeSitterHttp4kExtractor::Route, path : String) : Endpoint
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.form_params.each { |name| params << Param.new(name, "", "form") }
      params << Param.new("body", "", "json") if route.has_body?

      details = Details.new(PathInfo.new(path, route.line + 1))
      endpoint = Endpoint.new(route.path, route.verb, params, details)

      # 1-hop callees out of the handler expression. The Route
      # extractor doesn't carry the file path, so attach it here.
      route.callees.each do |entry|
        name, line = entry
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end

      endpoint
    end
  end
end
