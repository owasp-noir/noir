require "../../../models/analyzer"
require "set"

module Analyzer::R
  class Plumber < Analyzer
    HTTP_METHODS = Set{"GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"}

    # Matches lines like: #* @get /path or #* @post /path
    ROUTE_ANNOTATION = /@(get|post|put|delete|patch|head|options)\s+(\S+)/i

    # Matches lines like: #* @param name Description
    PARAM_ANNOTATION = /@param\s+([A-Za-z0-9_.-]+)(?:\s+(.*))?/i

    # Matches R function declaration: function(...)
    FUNCTION_DECLARATION = /\bfunction\s*\(([^)]*)\)/

    # Programmatic routes:
    # pr_get("/path", handler)
    PROGRAMMATIC_PIPELINE = /\bpr_(get|post|put|delete|patch|head|options)\s*\(\s*["']([^"']+)["']/i
    # pr_handle(pr, "GET", "/path", handler)
    PROGRAMMATIC_HANDLE = /\bpr_handle\s*\(\s*[^,]+,\s*["'](GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)["']\s*,\s*["']([^"']+)["']/i
    # r$get("/path", handler)
    PROGRAMMATIC_DOLLAR = /\$([a-z]+)\s*\(\s*["']([^"']+)["']/i
    # r$handle("GET", "/path", handler)
    PROGRAMMATIC_DOLLAR_HANDLE = /\$handle\s*\(\s*["'](GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)["']\s*,\s*["']([^"']+)["']/i

    def analyze
      r_files = get_files_by_extension(".R") + get_files_by_extension(".r")
      r_files = r_files.uniq.reject! { |path| File.directory?(path) }
      return @result if r_files.empty?

      r_files.each do |path|
        content = read_file_content(path)
        # Quick pre-check
        next unless content.includes?("#*") || content.includes?("plumber") || content.includes?("pr_") || content.includes?("$")

        process_file(path, strip_r_comments(content))
      end

      @result
    end

    private def strip_r_comments(text : String) : String
      result = String::Builder.new(text.bytesize)
      chars = text.chars
      i = 0
      size = chars.size

      while i < size
        c = chars[i]

        if c == '"' || c == '\''
          quote = c
          result << c
          i += 1
          while i < size
            ch = chars[i]
            if ch == '\\' && i + 1 < size
              result << ch
              result << chars[i + 1]
              i += 2
              next
            end
            result << ch
            i += 1
            break if ch == quote
          end
          next
        end

        if c == '#'
          if i + 1 < size && chars[i + 1] == '*'
            result << '#'
            result << '*'
            i += 2
            next
          else
            while i < size && chars[i] != '\n'
              i += 1
            end
            next
          end
        end

        result << c
        i += 1
      end

      result.to_s
    end

    private def process_file(path : String, content : String)
      lines = content.lines
      comments_block = [] of String
      comments_line_num = 0

      lines.each_with_index do |line, idx|
        trimmed = line.strip
        if trimmed.starts_with?("#*")
          if comments_block.empty?
            comments_line_num = idx + 1
          end
          comments_block << trimmed
        elsif !trimmed.empty?
          if !comments_block.empty?
            # We have a comments block followed by a non-empty line.
            # Parse route annotations from the block, and associate them with the function on this line
            parse_annotation_block(path, comments_block, comments_line_num, line, idx + 1)
            comments_block.clear
          end

          # Also check if this line contains programmatic routing
          parse_programmatic_routes(path, line, idx + 1)
        end
      end
    end

    private def parse_annotation_block(path : String, comments : Array(String), line_num : Int32, next_line : String, func_line_num : Int32)
      routes = [] of Tuple(String, String) # {method, path}
      param_descriptions = {} of String => String

      comments.each do |c|
        if m = c.match(ROUTE_ANNOTATION)
          method = m[1].upcase
          route_path = m[2]
          routes << {method, route_path}
        end

        if m = c.match(PARAM_ANNOTATION)
          param_name = m[1]
          desc = m[2]? || ""
          param_descriptions[param_name] = desc
        end
      end

      return if routes.empty?

      # Try to extract function arguments from next_line
      func_params = [] of String
      if m = next_line.match(FUNCTION_DECLARATION)
        args_str = m[1]
        func_params = parse_function_args(args_str)
      end

      routes.each do |route|
        method, raw_path = route
        normalized_path, path_params = normalize_path(raw_path)

        # Merge path parameters, function parameters, and @param annotations
        params = [] of Param
        seen_params = Set(String).new

        # 1. Path parameters first
        path_params.each do |p_name|
          seen_params.add(p_name)
          desc = param_descriptions[p_name]? || ""
          params << Param.new(p_name, desc, "path")
        end

        # 2. Function/annotation parameters next
        all_other_param_names = (func_params + param_descriptions.keys).uniq
        all_other_param_names.each do |p_name|
          next if seen_params.includes?(p_name)
          seen_params.add(p_name)

          desc = param_descriptions[p_name]? || ""
          # Location: body for POST/PUT/PATCH, query otherwise
          loc = (method == "POST" || method == "PUT" || method == "PATCH") ? "body" : "query"
          params << Param.new(p_name, desc, loc)
        end

        details = Details.new(PathInfo.new(path, line_num))
        @result << Endpoint.new(normalized_path, method, params, details)
      end
    end

    private def parse_function_args(args_str : String) : Array(String)
      names = [] of String
      # Simple parser that splits by comma, but skips commas inside quotes or nested parens
      depth = 0
      in_quote = false
      quote_char = ' '
      current = String::Builder.new
      chars = args_str.chars
      i = 0

      while i < chars.size
        c = chars[i]
        if in_quote
          if c == '\\' && i + 1 < chars.size
            i += 2
            next
          elsif c == quote_char
            in_quote = false
          end
          i += 1
          next
        end

        if c == '"' || c == '\''
          in_quote = true
          quote_char = c
          i += 1
          next
        end

        if c == '('
          depth += 1
        elsif c == ')'
          depth -= 1
        end

        if c == ',' && depth == 0
          # Split point
          arg = current.to_s.strip
          if !arg.empty?
            # Extract param name (before '=')
            name = arg.split('=').first.strip
            if name.matches?(/\A[A-Za-z0-9_.-]+\z/)
              names << name
            end
          end
          current = String::Builder.new
        else
          current << c
        end
        i += 1
      end

      # Add last argument
      arg = current.to_s.strip
      if !arg.empty?
        name = arg.split('=').first.strip
        if name.matches?(/\A[A-Za-z0-9_.-]+\z/)
          names << name
        end
      end

      names
    end

    private def normalize_path(raw_path : String) : Tuple(String, Array(String))
      path_params = [] of String
      # R plumber path parameters are in angle brackets: <id> or <id:int>
      # Replace <param:type> or <param> with :param
      normalized = raw_path.gsub(/<([^>]+)>/) do |match|
        inside = match[1...-1] # Strip angle brackets
        param_name = inside.split(':').first.strip
        path_params << param_name
        ":#{param_name}"
      end
      {normalized, path_params}
    end

    private def parse_programmatic_routes(path : String, line : String, line_num : Int32)
      # 1. pr_get(path, handler) / pr_post etc.
      line.scan(PROGRAMMATIC_PIPELINE) do |m|
        method = m[1].upcase
        raw_path = m[2]
        if HTTP_METHODS.includes?(method)
          normalized, path_params = normalize_path(raw_path)
          params = path_params.map { |name| Param.new(name, "", "path") }
          details = Details.new(PathInfo.new(path, line_num))
          @result << Endpoint.new(normalized, method, params, details)
        end
      end

      # 2. pr_handle(pr, "GET", "/path")
      line.scan(PROGRAMMATIC_HANDLE) do |m|
        method = m[1].upcase
        raw_path = m[2]
        if HTTP_METHODS.includes?(method)
          normalized, path_params = normalize_path(raw_path)
          params = path_params.map { |name| Param.new(name, "", "path") }
          details = Details.new(PathInfo.new(path, line_num))
          @result << Endpoint.new(normalized, method, params, details)
        end
      end

      # 3. r$get("/path")
      line.scan(PROGRAMMATIC_DOLLAR) do |m|
        method = m[1].upcase
        raw_path = m[2]
        if HTTP_METHODS.includes?(method)
          normalized, path_params = normalize_path(raw_path)
          params = path_params.map { |name| Param.new(name, "", "path") }
          details = Details.new(PathInfo.new(path, line_num))
          @result << Endpoint.new(normalized, method, params, details)
        end
      end

      # 4. r$handle("GET", "/path")
      line.scan(PROGRAMMATIC_DOLLAR_HANDLE) do |m|
        method = m[1].upcase
        raw_path = m[2]
        if HTTP_METHODS.includes?(method)
          normalized, path_params = normalize_path(raw_path)
          params = path_params.map { |name| Param.new(name, "", "path") }
          details = Details.new(PathInfo.new(path, line_num))
          @result << Endpoint.new(normalized, method, params, details)
        end
      end
    end
  end
end
