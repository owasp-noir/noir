require "../../../models/analyzer"

module Analyzer::Cpp
  class Crow < Analyzer
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp", ".hxx"]
    # CROW_ROUTE(app, "/path") — the app identifier and route literal.
    ROUTE_REGEX = /CROW_ROUTE\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*"([^"]*)"\s*\)/
    # CROW_BP_ROUTE(bp, "/path") — blueprint-scoped route registration.
    BP_ROUTE_REGEX = /CROW_BP_ROUTE\s*\(\s*[A-Za-z_][A-Za-z0-9_]*\s*,\s*"([^"]*)"\s*\)/
    # .methods("POST"_method, "GET"_method) clause.
    METHODS_REGEX = /\.methods\s*\(([^)]*)\)/
    METHOD_TOKEN  = /"([A-Za-z]+)"_method/
    # Path placeholder: <int>, <string>, <uint>, <double>, <path> — and the
    # non-standard but occasionally seen <type:name> form.
    PATH_PARAM_REGEX = /<([^<>:]+)(?::([^<>]+))?>/
    URL_PARAM_GET    = /url_params\s*\.\s*get\s*\(\s*"([^"]+)"/
    HEADER_VALUE     = /get_header_value\s*\(\s*"([^"]+)"/
    BODY_ACCESS      = /\breq\s*\.\s*body\b/

    def analyze
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_filtered_files(channel, CPP_EXTENSIONS)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          analyze_file(path)
        end
      rescue e
        logger.debug "Crow analyzer failed: #{e.message}"
      end

      result
    end

    private def analyze_file(path : String)
      source = read_file_content(path)
      return unless source.includes?("CROW_ROUTE") || source.includes?("CROW_BP_ROUTE")

      lines = source.split("\n")
      last_endpoints = [] of Endpoint

      lines.each_with_index do |line, index|
        route_match = line.match(ROUTE_REGEX) || line.match(BP_ROUTE_REGEX)
        if route_match
          route_path = route_match[1]

          # `.methods(...)` may sit on the same line as CROW_ROUTE or on one
          # of the following continuation lines before the handler lambda.
          search_window = line
          (1..3).each do |offset|
            break if index + offset >= lines.size
            next_line = lines[index + offset]
            break if next_line.match(ROUTE_REGEX) || next_line.match(BP_ROUTE_REGEX)
            search_window += " " + next_line
          end

          methods = [] of String
          if methods_match = search_window.match(METHODS_REGEX)
            methods_match[1].scan(METHOD_TOKEN) do |m|
              methods << m[1].upcase
            end
          end
          methods << "GET" if methods.empty?

          normalized_path, path_params = normalize_path(route_path)
          details = Details.new(PathInfo.new(path, index + 1))

          last_endpoints.clear
          methods.uniq.each do |method|
            endpoint = Endpoint.new(normalized_path, method, path_params.dup, details)
            result << endpoint
            last_endpoints << endpoint
          end
        else
          next if last_endpoints.empty?
          collect_params(line).each do |param|
            last_endpoints.each { |ep| push_unique(ep, param) }
          end
        end
      end
    end

    private def normalize_path(route_path : String) : Tuple(String, Array(Param))
      params = [] of Param
      counter = 0
      normalized = route_path.gsub(PATH_PARAM_REGEX) do |_|
        maybe_name = $~[2]?
        name = if maybe_name && !maybe_name.empty?
                 maybe_name
               else
                 counter += 1
                 "param#{counter}"
               end
        params << Param.new(name, "", "path")
        "{#{name}}"
      end
      {normalized, params}
    end

    private def collect_params(line : String) : Array(Param)
      params = [] of Param
      line.scan(URL_PARAM_GET) do |m|
        params << Param.new(m[1], "", "query")
      end
      line.scan(HEADER_VALUE) do |m|
        params << Param.new(m[1], "", "header")
      end
      if line.match(BODY_ACCESS)
        params << Param.new("body", "", "json")
      end
      params
    end

    private def push_unique(endpoint : Endpoint, param : Param)
      return if endpoint.params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      endpoint.push_param(param)
    end
  end
end
