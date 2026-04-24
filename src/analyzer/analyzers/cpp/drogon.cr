require "../../../models/analyzer"
require "wait_group"

module Analyzer::Cpp
  class Drogon < Analyzer
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp"]

    HTTP_METHODS = {
      "Get"     => "GET",
      "Post"    => "POST",
      "Put"     => "PUT",
      "Delete"  => "DELETE",
      "Patch"   => "PATCH",
      "Head"    => "HEAD",
      "Options" => "OPTIONS",
    }

    # `{Get, Post}` method list: brace block whose first token is a verb.
    METHOD_BLOCK = /\{\s*((?:drogon::)?(?:Get|Post|Put|Delete|Patch|Head|Options)\b[^{}]*)\}/

    REGEX_REGISTER_HANDLER = /app\(\)\s*\.?\s*registerHandler\s*\(\s*"([^"]+)"/
    REGEX_PATH_ADD         = /PATH_ADD\s*\(\s*"([^"]+)"\s*,\s*([^)]+)\)/
    REGEX_ADD_METHOD       = /ADD_METHOD_TO\s*\(\s*[^,]+\s*,\s*"([^"]+)"\s*,\s*([^)]+)\)/

    def analyze
      channel = Channel(String).new(DEFAULT_CHANNEL_CAPACITY)

      begin
        populate_channel_with_filtered_files(channel, CPP_EXTENSIONS)

        parallel_analyze(channel) do |path|
          next if File.directory?(path)
          next unless File.exists?(path)
          next unless CPP_EXTENSIONS.any? { |ext| path.ends_with?(ext) }

          content = read_file_content(path)
          next unless content.includes?("drogon") ||
                      content.includes?("registerHandler") ||
                      content.includes?("PATH_LIST_BEGIN") ||
                      content.includes?("PATH_ADD") ||
                      content.includes?("METHOD_LIST_BEGIN") ||
                      content.includes?("ADD_METHOD_TO")

          analyze_file(path, content)
        end
      rescue e
        logger.debug "Drogon analyzer failed: #{e.message}"
      end

      @result
    end

    def analyze_file(path : String, content : String)
      lines = content.split("\n")
      file_params = extract_params(lines)

      extract_register_handler_endpoints(path, content, lines, file_params).each do |endpoint|
        @result << endpoint
      end

      extract_block_endpoints(path, lines, "PATH_LIST_BEGIN", "PATH_LIST_END", REGEX_PATH_ADD, file_params).each do |endpoint|
        @result << endpoint
      end

      extract_block_endpoints(path, lines, "METHOD_LIST_BEGIN", "METHOD_LIST_END", REGEX_ADD_METHOD, file_params).each do |endpoint|
        @result << endpoint
      end
    end

    private def extract_register_handler_endpoints(path : String, content : String, lines : Array(String), file_params : Array(Param)) : Array(Endpoint)
      endpoints = [] of Endpoint

      # For each registerHandler("/path") occurrence, look ahead in the content
      # for the nearest method list block `{Get, Post, ...}`. This tolerates
      # lambda bodies between the path and the method list without needing a
      # full-blown C++ parser.
      content.scan(REGEX_REGISTER_HANDLER) do |match|
        route = normalize_path(match[1])
        rest = match.post_match
        window = rest.size > 4000 ? rest[0, 4000] : rest

        methods = if block_match = window.match(METHOD_BLOCK)
                    parse_methods(block_match[1])
                  else
                    ["GET"]
                  end

        line_number = find_line_number(lines, "registerHandler", match[1])

        methods.each do |m|
          details = Details.new(PathInfo.new(path, line_number))
          endpoint = Endpoint.new(route, m, details)
          file_params.each { |p| endpoint.push_param(p) }
          endpoints << endpoint
        end
      end

      endpoints
    end

    private def extract_block_endpoints(path : String, lines : Array(String), begin_marker : String, end_marker : String, pattern : Regex, file_params : Array(Param)) : Array(Endpoint)
      endpoints = [] of Endpoint
      in_block = false

      lines.each_with_index do |line, index|
        if line.includes?(begin_marker)
          in_block = true
          next
        end

        if line.includes?(end_marker)
          in_block = false
          next
        end

        next unless in_block

        if match = line.match(pattern)
          route = normalize_path(match[1])
          methods = parse_methods(match[2])

          methods.each do |m|
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint = Endpoint.new(route, m, details)
            file_params.each { |p| endpoint.push_param(p) }
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    private def parse_methods(raw : String) : Array(String)
      methods = [] of String
      raw.split(",").each do |token|
        name = token.strip.gsub(/^drogon::/, "").gsub(/^Http/, "").gsub(/Method$/, "")
        next if name.empty?
        if mapped = HTTP_METHODS[name]?
          methods << mapped unless methods.includes?(mapped)
        end
      end
      methods << "GET" if methods.empty?
      methods
    end

    # Normalize `/path/{id:int}` → `/path/{id}`; leaves plain `{id}` alone.
    private def normalize_path(path : String) : String
      path.gsub(/\{([^{}:]+):[^{}]+\}/) { "{#{$1}}" }
    end

    private def find_line_number(lines : Array(String), marker : String, route : String) : Int32
      lines.each_with_index do |line, index|
        return index + 1 if line.includes?(marker) && line.includes?(route)
      end
      1
    end

    private def extract_params(lines : Array(String)) : Array(Param)
      params = [] of Param

      lines.each do |line|
        if match = line.match(/->\s*getParameter\s*\(\s*"([^"]+)"/)
          add_unique_param(params, Param.new(match[1], "", "query"))
        end

        if match = line.match(/->\s*getOptionalParameter\s*<[^>]*>\s*\(\s*"([^"]+)"/)
          add_unique_param(params, Param.new(match[1], "", "query"))
        end

        if match = line.match(/->\s*getHeader\s*\(\s*"([^"]+)"/)
          add_unique_param(params, Param.new(match[1], "", "header"))
        end

        if match = line.match(/->\s*getCookie\s*\(\s*"([^"]+)"/)
          add_unique_param(params, Param.new(match[1], "", "cookie"))
        end

        if line.includes?("->getJsonObject(") || line.includes?("->getJsonValue(")
          add_unique_param(params, Param.new("body", "", "json"))
        end

        if line.matches?(/->\s*(body|getBody)\s*\(\s*\)/) &&
           !line.includes?("->getJsonObject(") && !line.includes?("->getJsonValue(")
          add_unique_param(params, Param.new("body", "", "body"))
        end
      end

      params
    end

    private def add_unique_param(params : Array(Param), param : Param)
      return if param.name.empty?
      return if params.any? { |p| p.name == param.name && p.param_type == param.param_type }
      params << param
    end
  end
end
