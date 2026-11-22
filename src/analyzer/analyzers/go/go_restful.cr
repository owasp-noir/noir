require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  # go-restful (`github.com/emicklei/go-restful`) — a WebService-centric
  # router used across the cloud-native ecosystem (Kubernetes' apiserver,
  # Harbor, …). Routes are a nested builder chain hung off a WebService
  # whose `Path()` supplies the prefix:
  #
  #   ws := new(restful.WebService)
  #   ws.Path("/users")
  #   ws.Route(ws.GET("/{user-id}").To(u.findUser).
  #       Param(ws.PathParameter("user-id", "identifier")).
  #       Reads(User{}))
  #
  # The extractor resolves the full mounted path and the self-declared
  # params; this analyzer wires endpoints, params, and 1-hop callees.
  class GoRestful < GoEngine
    analyzer_for "go_restful"

    def normalize_restful_path(path : String) : String
      Noir::URLPath.normalize(path, Noir::URLPath::BRACE_CONSTRAINT, rooted: false)
    end

    IMPORT_MARKER = "github.com/emicklei/go-restful"

    # One precompiled matcher instead of a `String#includes?` scan per
    # `.go` file: `includes?` runs Rabin-Karp over the whole buffer and
    # the marker is absent in the overwhelming majority of files in a
    # polyglot repo, so every one of them pays the full scan. See
    # `Analyzer#content_matches?`.
    IMPORT_MARKER_RE = Regex.union(IMPORT_MARKER)

    def analyze
      file_contents = read_package_file_contents
      package_function_bodies = lazy_package_bodies(file_contents)
      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if go_test_path?(path)
        next unless File.exists?(path)

        content = file_contents[path]? || read_file_content(path)
        next unless content_matches?(content, IMPORT_MARKER_RE)

        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_go_restful_routes(content)
        next if ts_routes.empty?

        route_offsets = ts_routes.map(&.offset).to_set
        external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
        callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_offsets, external_fns)

        ts_routes.each do |route|
          details = Details.new(PathInfo.new(path, route.line + 1))
          endpoint = Endpoint.new(normalize_restful_path(route.path), route.verb, details)

          route.params.each do |name, param_in|
            param = Param.new(name, "", param_in)
            endpoint.params << param unless endpoint.params.includes?(param)
          end

          if entries = callees_by_route[route.offset]?
            entries.each do |entry|
              callee_name, callee_path, callee_line = entry
              endpoint.push_callee(Callee.new(callee_name, path: callee_path, line: callee_line))
            end
          end

          result << endpoint
        end
      end

      result
    end
  end
end
