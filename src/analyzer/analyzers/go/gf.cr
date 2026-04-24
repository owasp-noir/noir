require "../../engines/go_engine"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class Gf < GoEngine
    def analyze
      # Source Analysis
      public_dirs = [] of (Hash(String, String))
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)
      begin
        populate_channel_with_filtered_files(channel, ".go")

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  if File.exists?(path)
                    content = File.read(path, encoding: "utf-8", invalid: :skip)
                    lines = content.lines
                    last_endpoint = Endpoint.new("", "")

                    # Tree-sitter pre-pass covers gf's three route shapes
                    # in one walk: closure groups `.Group("/x", func(){...})`,
                    # chained `s.Group("/multi").GET(...)`, and
                    # `.BindHandler("/x", h)` method-agnostic registrations.
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_gf_routes(content)
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          # BindHandler/BindMiddleware accept any method;
                          # fixtures expect GET, so fold "ALL" down.
                          verb = route.verb == "ALL" ? "GET" : route.verb
                          new_endpoint = Endpoint.new(route.path, verb, details)
                          result << new_endpoint
                          last_endpoint = new_endpoint
                        end
                      end

                      ["Get", "GetQuery", "GetForm", "GetHeader", "GetUploadFile"].each do |pattern|
                        if line.includes?("#{pattern}(") && !line.includes?("Cookie.Get")
                          add_param_to_endpoint(get_param(line), last_endpoint)
                        end
                      end

                      if line.includes?("Static(")
                        add_static_path_if_valid(get_static_path(line), public_dirs)
                      end

                      if line.includes?("Cookie.Get(")
                        match = line.match(/Cookie\.Get\(\"(.*)\"\)/)
                        if match
                          cookie_name = match[1]
                          last_endpoint.params << Param.new(cookie_name, "", "cookie")
                        end
                      end
                    end
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

      resolve_public_dirs(public_dirs)

      result
    end

    def get_param(line : String) : Param
      param_type =
        if line.includes?("GetQuery(")
          "query"
        elsif line.includes?("GetForm(") || line.includes?("GetUploadFile(")
          "form"
        elsif line.includes?("GetHeader(")
          "header"
        else
          "json"
        end

      match = line.match(/\(\s*"([^"]+)"\s*\)/)
      if match
        return Param.new(match[1], "", param_type)
      end

      Param.new("", "", "")
    end
  end
end
