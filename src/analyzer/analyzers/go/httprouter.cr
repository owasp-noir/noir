require "../../../models/analyzer"
require "../../../miniparsers/go_route_extractor_ts"

module Analyzer::Go
  class Httprouter < Analyzer
    PARAM_PATTERNS = [
      {"ByName(", /ByName\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "path"},
      {"Query().Get(", /Query\(\)\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "query"},
      {"PostFormValue(", /PostFormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "form"},
      {"Header.Get(", /Header\s*\.\s*Get\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "header"},
      {"Cookie(", /Cookie\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "cookie"},
    ]

    def analyze
      # Source Analysis
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

                    # Tree-sitter pre-pass: httprouter exposes HTTP verbs as
                    # methods on the router AND a `Handle("METHOD", "/path",
                    # handler)` shape where the method is the first argument.
                    # Pass `handle_method: "Handle"` so both shapes resolve in
                    # a single parse. httprouter has no groups, so we don't
                    # pass any cross-file group map.
                    ts_routes = Noir::TreeSitterGoRouteExtractor.extract_routes(
                      content, handle_method: "Handle")
                    routes_by_line = Hash(Int32, Array(Noir::TreeSitterGoRouteExtractor::Route)).new
                    ts_routes.each do |r|
                      routes_by_line[r.line] ||= [] of Noir::TreeSitterGoRouteExtractor::Route
                      routes_by_line[r.line] << r
                    end

                    lines.each_with_index do |line, index|
                      details = Details.new(PathInfo.new(path, index + 1))

                      if ts_hits = routes_by_line[index]?
                        ts_hits.each do |route|
                          last_endpoint = add_endpoint(route.path, route.verb, details)
                        end
                      end

                      # FormValue must be checked separately to avoid matching PostFormValue
                      if line.includes?("FormValue(") && !line.includes?("PostFormValue(")
                        extract_param(line, /(?<!Post)FormValue\s*\(\s*[\"']([^\"']+)[\"']\s*\)/, "query", last_endpoint)
                      end

                      PARAM_PATTERNS.each do |includes_check, regex, param_type|
                        if line.includes?(includes_check)
                          extract_param(line, regex, param_type, last_endpoint)
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

      result
    end

    private def add_endpoint(route_path : String, method : String, details : Details) : Endpoint
      if route_path.size > 0
        new_endpoint = Endpoint.new(route_path, method, details)
        result << new_endpoint
        new_endpoint
      else
        Endpoint.new("", "")
      end
    end

    private def extract_param(line : String, regex : Regex, param_type : String, endpoint : Endpoint)
      if param_match = line.match(regex)
        param_name = param_match[1]
        if param_name.size > 0 && endpoint.url != ""
          endpoint.params << Param.new(param_name, "", param_type)
        end
      end
    end
  end
end
