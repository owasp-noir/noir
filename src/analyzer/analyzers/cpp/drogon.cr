require "../../../models/analyzer"
require "../../../miniparsers/cpp_callee_extractor"
require "wait_group"

module Analyzer::Cpp
  class Drogon < Analyzer
    CPP_EXTENSIONS = [".cpp", ".cc", ".cxx", ".h", ".hpp"]
    alias HandlerTarget = Tuple(String?, String)
    alias SourceRange = Tuple(Int32, Int32)

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
    REGEX_ADD_METHOD       = /ADD_METHOD_TO\s*\(\s*([^,]+)\s*,\s*"([^"]+)"\s*,\s*([^)]+)\)/

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?)
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

          analyze_file(path, content, include_callee)
        end
      rescue e
        logger.debug "Drogon analyzer failed: #{e.message}"
      end

      @result
    end

    def analyze_file(path : String, content : String, include_callee : Bool = false)
      lines = content.split("\n")
      file_params = extract_params(lines)

      extract_register_handler_endpoints(path, content, lines, file_params, include_callee).each do |endpoint|
        @result << endpoint
      end

      extract_block_endpoints(path, lines, "PATH_LIST_BEGIN", "PATH_LIST_END", REGEX_PATH_ADD, file_params).each do |endpoint|
        @result << endpoint
      end

      extract_add_method_endpoints(path, content, lines, file_params, include_callee).each do |endpoint|
        @result << endpoint
      end
    end

    private def extract_register_handler_endpoints(path : String, content : String, lines : Array(String), file_params : Array(Param), include_callee : Bool) : Array(Endpoint)
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
        match_start = match.begin(0) || 0
        callees = include_callee ? callees_for_block_after(content, path, match_start) : [] of Noir::CppCalleeExtractor::Entry

        methods.each do |m|
          details = Details.new(PathInfo.new(path, line_number))
          endpoint = Endpoint.new(route, m, details)
          file_params.each { |p| endpoint.push_param(p) }
          Noir::CppCalleeExtractor.attach_to(endpoint, callees) if include_callee
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

    private def extract_add_method_endpoints(path : String,
                                             content : String,
                                             lines : Array(String),
                                             file_params : Array(Param),
                                             include_callee : Bool) : Array(Endpoint)
      endpoints = [] of Endpoint
      in_block = false

      lines.each_with_index do |line, index|
        if line.includes?("METHOD_LIST_BEGIN")
          in_block = true
          next
        end

        if line.includes?("METHOD_LIST_END")
          in_block = false
          next
        end

        next unless in_block

        if match = line.match(REGEX_ADD_METHOD)
          handler_target = normalize_handler_target(match[1])
          route = normalize_path(match[2])
          methods = parse_methods(match[3])
          callees = include_callee ? callees_for_handler(content, path, handler_target) : [] of Noir::CppCalleeExtractor::Entry

          methods.each do |m|
            details = Details.new(PathInfo.new(path, index + 1))
            endpoint = Endpoint.new(route, m, details)
            file_params.each { |p| endpoint.push_param(p) }
            Noir::CppCalleeExtractor.attach_to(endpoint, callees) if include_callee
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    private def callees_for_block_after(content : String, path : String, search_start : Int32) : Array(Noir::CppCalleeExtractor::Entry)
      block = Noir::CppCalleeExtractor.extract_block_after(content, search_start)
      return [] of Noir::CppCalleeExtractor::Entry unless block

      body, start_line = block
      Noir::CppCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def callees_for_handler(content : String, path : String, handler_target : HandlerTarget) : Array(Noir::CppCalleeExtractor::Entry)
      block = extract_method_body(content, handler_target)
      return [] of Noir::CppCalleeExtractor::Entry unless block

      body, start_line = block
      Noir::CppCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def extract_method_body(content : String, handler_target : HandlerTarget) : Tuple(String, Int32)?
      owner, method_name = handler_target
      return if method_name.empty?

      if owner
        class_range = class_body_range(content, owner)
        if class_range
          body = extract_method_body_in_range(content, Regex.escape(method_name), class_range)
          return body if body
        end

        extract_method_body_in_range(content, "#{Regex.escape(owner)}\\s*::\\s*#{Regex.escape(method_name)}", {0, content.bytesize})
      else
        extract_method_body_in_range(content, Regex.escape(method_name), {0, content.bytesize})
      end
    end

    private def extract_method_body_in_range(content : String, method_pattern : String, range : SourceRange) : Tuple(String, Int32)?
      range_start, range_end = range
      content.scan(/\b#{method_pattern}\s*\(/) do |match|
        match_start = match.begin(0) || 0
        next if match_start < range_start || match_start >= range_end
        next if call_context?(content, match_start)

        open_paren = Noir::CppCalleeExtractor.find_next_code_char(content, '(', match_start)
        next unless open_paren

        close_paren = Noir::CppCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
        next unless close_paren

        body_open = Noir::CppCalleeExtractor.find_next_code_char(content, '{', close_paren + 1)
        next unless body_open
        next if body_open > range_end
        next unless method_suffix?(content[(close_paren + 1)...body_open])

        semicolon = Noir::CppCalleeExtractor.find_next_code_char(content, ';', close_paren + 1)
        next if semicolon && semicolon < body_open

        body_close = Noir::CppCalleeExtractor.find_matching_delimiter(content, body_open, '{', '}')
        next unless body_close

        return {content[(body_open + 1)...body_close], Noir::CppCalleeExtractor.line_number_for(content, body_open)}
      end

      nil
    end

    private def class_body_range(content : String, class_name : String) : SourceRange?
      content.scan(/\b(?:class|struct)\s+#{Regex.escape(class_name)}\b/) do |match|
        class_start = match.begin(0) || 0
        open_brace = Noir::CppCalleeExtractor.find_next_code_char(content, '{', class_start)
        next unless open_brace

        close_brace = Noir::CppCalleeExtractor.find_matching_delimiter(content, open_brace, '{', '}')
        next unless close_brace

        return {open_brace + 1, close_brace}
      end

      nil
    end

    private def method_suffix?(suffix : String) : Bool
      normalized = suffix.gsub(/noexcept\s*\([^)]*\)/, "noexcept")
      normalized.matches?(/\A[\sA-Za-z0-9_:<>,*&\-\[\]]*\z/)
    end

    private def call_context?(content : String, index : Int32) : Bool
      previous = previous_code_char(content, index)
      previous == '(' || previous == '.' || previous == '>' || previous == ':'
    end

    private def previous_code_char(content : String, index : Int32) : Char?
      cursor = index - 1
      while cursor >= 0
        char = content.byte_at(cursor).unsafe_chr
        return char unless char.whitespace?

        cursor -= 1
      end

      nil
    end

    private def normalize_handler_target(raw : String) : HandlerTarget
      target = raw.strip.lchop('&').strip
      parts = target.split("::").map(&.strip).reject(&.empty?)
      method_name = parts.last? || target
      owner = parts.size > 1 ? parts[-2] : nil
      {owner, method_name}
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
