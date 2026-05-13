require "../../engines/php_engine"

module Analyzer::Php
  class Php < PhpEngine
    def analyze_file(path : String) : Array(Endpoint)
      return [] of Endpoint unless File.extname(path) == ".php"

      endpoints = [] of Endpoint
      relative_path = get_relative_path(base_path, path)
      include_callee = any_to_bool(@options["include_callee"]?)

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        params_query = [] of Param
        params_body = [] of Param
        methods = [] of String

        content.each_line do |line|
          if allow_patterns.any? { |pattern| line.includes? pattern }
            match = line.strip.match(/\$_(.*?)\['(.*?)'\]/)

            if match
              method = match[1]
              param_name = match[2]

              if method == "GET"
                params_query << Param.new(param_name, "", "query")
              elsif method == "POST"
                params_body << Param.new(param_name, "", "form")
                methods << "POST"
              elsif method == "REQUEST"
                params_query << Param.new(param_name, "", "query")
                params_body << Param.new(param_name, "", "form")
                methods << "POST"
              elsif method == "SERVER"
                if param_name.includes? "HTTP_"
                  param_name = param_name.sub("HTTP_", "").gsub("_", "-")
                  params_query << Param.new(param_name, "", "header")
                  params_body << Param.new(param_name, "", "header")
                end
              end
            end
          end
        rescue
          next
        end

        details = Details.new(PathInfo.new(path))
        methods.each do |method|
          endpoints << Endpoint.new("/#{relative_path}", method, params_body, details)
        end
        endpoints << Endpoint.new("/#{relative_path}", "GET", params_query, details)
        attach_file_callees(endpoints, content, path) if include_callee
      end

      endpoints
    end

    private def attach_file_callees(endpoints : Array(Endpoint), content : String, path : String)
      callees = Noir::PhpCalleeExtractor.callees_for_body(executable_file_content(content), path, 1)
      endpoints.each do |endpoint|
        attach_php_callees(endpoint, callees)
      end
    end

    private def executable_file_content(content : String) : String
      declaration_ranges = [] of Tuple(Int32, Int32)
      declaration_regex = /\b(?:abstract\s+|final\s+)?(?:class|interface|trait|enum)\s+[A-Za-z_]\w*[^{]*\{|\bfunction\s+&?\s*[A-Za-z_]\w*[^{]*\{/m
      offset = 0

      while offset < content.size
        match = declaration_regex.match(content, offset)
        break unless match

        brace_pos = match.end(0) - 1
        close_pos = find_matching_php_close_brace(content, brace_pos)
        unless close_pos
          offset = match.end(0)
          next
        end

        declaration_ranges << {match.begin(0), close_pos + 1}
        offset = close_pos + 1
      end

      return content if declaration_ranges.empty?

      blank_ranges(content, declaration_ranges)
    end

    private def blank_ranges(content : String, ranges : Array(Tuple(Int32, Int32))) : String
      String.build do |io|
        offset = 0
        ranges.each do |range_start, range_end|
          io << content[offset...range_start]
          io << blank_preserving_newlines(content[range_start...range_end])
          offset = range_end
        end
        io << content[offset..]
      end
    end

    private def blank_preserving_newlines(content : String) : String
      String.build do |io|
        content.each_char do |char|
          io << (char == '\n' ? '\n' : ' ')
        end
      end
    end

    def allow_patterns
      ["$_GET", "$_POST", "$_REQUEST", "$_SERVER"]
    end
  end
end
