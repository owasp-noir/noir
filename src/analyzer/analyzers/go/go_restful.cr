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
    IMPORT_MARKER = "github.com/emicklei/go-restful"

    def analyze
      file_contents = read_package_file_contents
      package_function_bodies = collect_package_function_bodies(file_contents)
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        WaitGroup.wait do |wg|
          # Producer — tracked by the WaitGroup
          wg.spawn do
            get_files_by_extension(".go").each { |file| channel.send(file) }
            channel.close
          end

          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  next if GoEngine.go_test_file?(path)
                  next unless File.exists?(path)

                  content = file_contents[path]? || read_file_content(path)
                  next unless content.includes?(IMPORT_MARKER)

                  ts_routes = Noir::TreeSitterGoRouteExtractor.extract_go_restful_routes(content)
                  next if ts_routes.empty?

                  route_rows = Set(Int32).new
                  ts_routes.each { |r| route_rows << r.line }
                  external_fns = ts_function_bodies_for_directory(package_function_bodies, File.dirname(path))
                  callees_by_route = Noir::GoCalleeExtractor.callees_for_routes_if(callees_needed?, content, path, route_rows, external_fns)

                  ts_routes.each do |route|
                    details = Details.new(PathInfo.new(path, route.line + 1))
                    endpoint = Endpoint.new(normalize_restful_path(route.path), route.verb, details)

                    route.params.each do |name, param_in|
                      param = Param.new(name, "", param_in)
                      endpoint.params << param unless endpoint.params.includes?(param)
                    end

                    if entries = callees_by_route[route.line]?
                      entries.each do |entry|
                        callee_name, callee_path, callee_line = entry
                        endpoint.push_callee(Callee.new(callee_name, path: callee_path, line: callee_line))
                      end
                    end

                    result << endpoint
                  end
                rescue File::NotFoundError
                  logger.debug "File not found: #{path}"
                end
              end
            end
          end
        end
      rescue e
        logger.debug e
      end

      result
    end

    # go-restful path params are `{name}`, with an optional tail/regex
    # constraint `{name:*}` / `{name:[0-9]+}`; strip the constraint so the
    # template reads as a clean `{name}` (mirrors the Iris normalizer).
    def normalize_restful_path(path : String) : String
      path.gsub(/\{([^{}:]+):[^{}]+\}/) { "{#{$1}}" }
    end
  end
end
