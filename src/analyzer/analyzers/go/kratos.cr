require "../../../models/analyzer"
require "../../../miniparsers/go_callee_extractor"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  # Kratos (https://go-kratos.dev/) is a Go microservices framework whose
  # HTTP surface is (almost always) generated from `.proto` service
  # definitions by `protoc-gen-go-http`, not hand-registered. A generated
  # `*_http.pb.go` file looks like:
  #
  #   func RegisterTodoServiceHTTPServer(s *http.Server, srv TodoServiceHTTPServer) {
  #       r := s.Route("/")
  #       r.Handle("POST", "/v1/todos/create", _TodoService_CreateTodo0_HTTP_Handler(srv))
  #       r.Handle("GET", "/v1/todos/{id}", _TodoService_GetTodo0_HTTP_Handler(srv))
  #   }
  #
  # protoc-gen-go-http v3+ emits the method-first `r.Handle("METHOD",
  # "path", handler)` shape shown above; v2.x (still the majority of
  # deployed Kratos services) emits verb shortcuts instead
  # (`r.GET("/v1/todos/{id}", handler)`, `r.POST(...)`, ...). The shared
  # tree-sitter Go route walker already recognises both shapes (it backs
  # httprouter's analyzer for the same `Handle` + verb-method combo), so
  # this analyzer is a thin Kratos-specific wrapper around it rather than
  # a bespoke parser.
  #
  # Path params (`{id}`) are left in the URL as-is; `EndpointOptimizer`
  # derives `Param` entries from `{...}` placeholders for every analyzer,
  # so they don't need to be extracted here.
  class Kratos < Analyzer
    analyzer_for "go_kratos"

    # Only `.go` files that import Kratos' own HTTP transport package
    # are scanned. This is a narrow, framework-specific marker — unlike
    # a bare `.GET("/path", handler)` call, which virtually any Go
    # router could produce — so a Kratos-tagged repository never steals
    # routes registered by a sibling framework living in the same tree
    # (see the analyzer project-scoping campaign, #2417-2432). Matches
    # both `github.com/go-kratos/kratos/v2/transport/http` and the
    # newer `v3` module path.
    IMPORT_MARKER = /go-kratos\/kratos\/v\d+\/transport\/http/

    # HTTP methods protoc-gen-go-http allows a `google.api.http` body
    # rule on. The generator itself enforces (and warns at generation
    # time when violated) that only these verbs bind a request body —
    # GET/DELETE never do. Field-level body/query shapes require the
    # paired `.proto`/generated request struct, which this analyzer
    # does not parse, so a generic `body` param is attached instead
    # (mirrors the connect_rpc analyzer's level of detail).
    BODY_VERBS = {"POST", "PUT", "PATCH"}

    def analyze
      file_contents = Hash(String, String).new
      get_files_by_extension(".go").each do |fp|
        file_contents[fp] = read_file_content(fp)
      rescue IO::Error
        # skip
      end
      package_function_bodies = Noir::GoCalleeExtractor.package_function_bodies_if(callees_needed?, file_contents)

      parallel_analyze(get_files_by_extension(".go")) do |path|
        next if GoEngine.go_test_file?(base_relative_path(path))
        next unless File.exists?(path)
        content = file_contents[path]? || read_file_content(path)
        next unless content_matches?(content, IMPORT_MARKER)

        # `group_method: "Route"` resolves `r := s.Route("/prefix")` so a
        # hand-written non-root mount composes correctly; generated code
        # always passes "/" and already embeds the full path in the
        # literal, so the common case is a no-op here. `handle_method:
        # "Handle"` covers the v3+ method-first shape; the verb shortcuts
        # (`r.GET`, `r.POST`, ...) are recognised unconditionally by the
        # shared walker.
        ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
          content, group_method: "Route", handle_method: "Handle")
        next if ts_routes.empty?

        route_rows = Set(Int32).new
        ts_routes.each { |r| route_rows << r.line }
        external_fns = Noir::GoCalleeExtractor.function_bodies_for_directory(package_function_bodies, File.dirname(path))
        callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

        ts_routes.each do |route|
          details = Details.new(PathInfo.new(path, route.line + 1))

          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |verb|
            endpoint = Endpoint.new(route.path, verb, details)

            endpoint.params << Param.new("body", "", "json") if BODY_VERBS.includes?(verb)

            if entries = callees_by_route[route.line]?
              entries.each do |entry|
                name, callee_path, callee_line = entry
                endpoint.push_callee(Callee.new(name, path: callee_path, line: callee_line))
              end
            end

            result << endpoint
          end
        end
      end

      result
    end
  end
end
