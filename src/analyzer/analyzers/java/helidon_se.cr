require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/helidon_se_extractor_ts"
require "../../../utils/url_path"

module Analyzer::Java
  # Helidon SE's routing table is composed two ways at once: inline verb
  # calls directly on a `HttpRouting.Builder`/`HttpRules`, and modular
  # `HttpService` classes mounted elsewhere via
  # `builder.register("/prefix", new SomeService())`. The second shape —
  # one `HttpService` per resource, wired up from a separate `Main`
  # class — is what every Helidon-published quickstart/example uses, so
  # getting only the first shape right would miss the prefix on nearly
  # every real route.
  #
  # `TreeSitterHelidonSeExtractor` reports the two shapes per file:
  # verb calls tagged by their enclosing class, and `.register(...)`
  # edges tagged by (enclosing class, target class). This analyzer
  # aggregates both across every Helidon-marked file in a project root
  # and resolves the resulting mount graph — classes are matched by
  # simple name, root-scoped, the same approximation the JAX-RS
  # analyzer's bean/subresource indices and the Micronaut analyzer's
  # interface-route index already make for cross-file linkage.
  class HelidonSe < Analyzer
    analyzer_for "java_helidon_se"

    JAVA_EXTENSION = "java"

    # `io.helidon.webserver` covers the `HttpRouting`/`HttpService`/
    # `HttpRules`/`WebServer` types across Helidon 2.x-4.x — a class
    # that implements `HttpService` or builds a `HttpRouting.Builder`
    # necessarily imports (or fully-qualifies) something under this
    # package, so a single substring check is a genuine positive
    # signal rather than "any Java file with `.get(...)` calls".
    HELIDON_SE_MARKER_RE = Regex.union("io.helidon.webserver")

    alias Route = Noir::TreeSitterHelidonSeExtractor::Route
    alias RegisterEdge = Noir::TreeSitterHelidonSeExtractor::RegisterEdge

    def analyze
      include_callee = callees_needed?

      # project_root => class_name => [(Route, file_path)]
      routes_by_root = Hash(String, Hash(String, Array(Tuple(Route, String)))).new
      # project_root => [RegisterEdge]
      edges_by_root = Hash(String, Array(RegisterEdge)).new

      all_files().each do |path|
        next if JavaEngine.test_path?(base_relative_path(path))
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless content_matches?(content, HELIDON_SE_MARKER_RE)

        result = Noir::TreeSitterHelidonSeExtractor.extract(content, include_callees: include_callee)
        next if result.routes.empty? && result.edges.empty?

        root = project_root_for(path)
        routes_for_root = routes_by_root[root] ||= Hash(String, Array(Tuple(Route, String))).new
        result.routes.each do |route|
          (routes_for_root[route.class_name] ||= [] of Tuple(Route, String)) << {route, path}
        end
        (edges_by_root[root] ||= [] of RegisterEdge).concat(result.edges)
      end

      routes_by_root.each do |root, routes_by_class|
        prefixes = resolve_prefixes(routes_by_class.keys, edges_by_root[root]? || [] of RegisterEdge)

        routes_by_class.each do |class_name, entries|
          class_prefixes = prefixes[class_name]? || Set{""}

          entries.each do |entry|
            route, path = entry
            params = params_for(route)
            line = route.line + 1

            class_prefixes.each do |prefix|
              details = Details.new(PathInfo.new(path, line))
              endpoint = Endpoint.new(Noir::URLPath.join_trimmed(prefix, route.path), route.verb, params, details)
              endpoint.protocol = route.protocol
              route.callees.each do |callee_entry|
                name, callee_line = callee_entry
                endpoint.push_callee(Callee.new(name, path: path, line: callee_line))
              end
              @result << endpoint
            end
          end
        end
      end

      Fiber.yield
      @result
    end

    private def params_for(route : Route) : Array(Param)
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.cookie_params.each { |name| params << Param.new(name, "", "cookie") }
      if route.has_body?
        params << Param.new("body", route.body_type || "", "json")
      end
      params
    end

    # Resolve, per class, every prefix it's reachable at by following
    # `.register(prefix, new Target())` edges from root mounts (classes
    # that are never themselves a register target — the composer that
    # wires everything to the `WebServer`). A class untouched by any
    # edge (including one that's a target nobody ever reached) falls
    # back to the empty prefix rather than silently dropping its
    # routes — matches the rest of noir's "best-effort over dropped"
    # posture when cross-file linkage can't be fully resolved.
    private def resolve_prefixes(classes_with_routes : Array(String), edges : Array(RegisterEdge)) : Hash(String, Set(String))
      prefixes = Hash(String, Set(String)).new
      targets = edges.map(&.target_class).to_set

      classes_with_routes.each do |name|
        prefixes[name] = Set{""} unless targets.includes?(name)
      end
      edges.each do |edge|
        prefixes[edge.source_class] ||= Set{""} unless targets.includes?(edge.source_class)
      end

      # Bounded fixed-point over a typically tiny graph; the bound (not
      # a bare `changed`-flag loop) keeps a register() cycle from
      # spinning forever while still giving every realistic nesting
      # depth room to converge.
      (edges.size + 8).times do
        changed = false
        edges.each do |edge|
          next unless source_prefixes = prefixes[edge.source_class]?
          target_prefixes = prefixes[edge.target_class] ||= Set(String).new

          source_prefixes.each do |source_prefix|
            joined = Noir::URLPath.join_trimmed(source_prefix, edge.prefix)
            next if target_prefixes.includes?(joined)
            target_prefixes << joined
            changed = true
          end
        end
        break unless changed
      end

      classes_with_routes.each do |name|
        existing = prefixes[name]?
        prefixes[name] = Set{""} if existing.nil? || existing.empty?
      end

      prefixes
    end

    private def project_root_for(path : String) : String
      marker = "/src/main/java/"
      if index = path.index(marker)
        path[...index]
      else
        File.dirname(path)
      end
    end
  end
end
