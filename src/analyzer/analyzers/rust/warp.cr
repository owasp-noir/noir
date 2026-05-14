require "../../engines/rust_engine"

module Analyzer::Rust
  class Warp < RustEngine
    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      content = read_file_content(path)
      include_callee = any_to_bool(@options["include_callee"]?)
      function_callees = include_callee ? collect_function_callees(content.lines, path) : Hash(String, Array(Noir::RustCalleeExtractor::Entry)).new

      # Simple approach: split by let statements and analyze each
      statements = content.split(/(?=let\s+\w+\s*=)/)
      statements.each do |statement|
        if statement.includes?("warp::") && (statement.includes?("get()") || statement.includes?("post()") || statement.includes?("put()") || statement.includes?("delete()"))
          endpoint = parse_warp_statement(statement, path)
          if endpoint
            attach_handler_callees(statement, function_callees, endpoint) if include_callee
            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    private def parse_warp_statement(statement : String, file_path : String) : Endpoint?
      # Extract HTTP method
      method = "GET"
      if statement.includes?("warp::get()")
        method = "GET"
      elsif statement.includes?("warp::post()")
        method = "POST"
      elsif statement.includes?("warp::put()")
        method = "PUT"
      elsif statement.includes?("warp::delete()")
        method = "DELETE"
      end

      # Build path
      path_parts = [] of String
      params = [] of Param

      # Check for root path (path::end without explicit path)
      if statement.includes?("warp::path::end()") && !statement.includes?("warp::path(\"")
        details = Details.new(PathInfo.new(file_path, 1))

        # Still check for parameters even on root path
        extract_non_path_params(statement, params)

        return Endpoint.new("/", method, params, details)
      end

      # Extract explicit path segments
      statement.scan(/warp::path\("([^"]+)"\)/) do |match|
        if match.size > 1
          path_parts << match[1]
        end
      end

      # Count parameters and add them to both path and params array
      param_count = statement.scan(/warp::path::param/).size
      param_count.times do |i|
        param_name = "param"
        if param_count > 1
          param_name = "param#{i + 1}"
        end
        path_parts << ":#{param_name}"
        params << Param.new(param_name, "", "path")
      end

      if path_parts.empty?
        return
      end

      route_path = "/" + path_parts.join("/")

      # Extract query, body, header, and cookie parameters
      extract_non_path_params(statement, params)

      details = Details.new(PathInfo.new(file_path, 1))
      Endpoint.new(route_path, method, params, details)
    rescue
      nil
    end

    private def collect_function_callees(lines : Array(String), path : String) : Hash(String, Array(Noir::RustCalleeExtractor::Entry))
      function_callees = Hash(String, Array(Noir::RustCalleeExtractor::Entry)).new
      in_block_comment = false
      index = 0

      while index < lines.size
        stripped, in_block_comment = Noir::RustCalleeExtractor.strip_comment_with_state(lines[index], in_block_comment)
        match = stripped.strip.match(/^(?:pub(?:\([^)]*\))?\s+)?(?:async\s+|const\s+|unsafe\s+)*fn\s+([A-Za-z_]\w*)\b/)

        if match
          function_body = extract_rust_function_body_with_end(lines, index)
          if function_body
            body, body_start_line, end_index = function_body
            function_callees[match[1]] = Noir::RustCalleeExtractor.callees_for_body(body, path, body_start_line)
            index = end_index
            in_block_comment = false
          end
        end

        index += 1
      end

      function_callees
    end

    private def attach_handler_callees(statement : String,
                                       function_callees : Hash(String, Array(Noir::RustCalleeExtractor::Entry)),
                                       endpoint : Endpoint)
      handler_name = extract_handler_name(statement)
      return unless handler_name

      if callees = function_callees[handler_name]?
        attach_rust_callees(endpoint, callees)
      end
    end

    private def extract_handler_name(statement : String) : String?
      match = statement.match(/\.(?:map|and_then|then)\s*\(\s*((?:[A-Za-z_]\w*::)*[A-Za-z_]\w*)(?:::<[^>]+>)?\s*\)/)
      return unless match

      match[1].split("::").last
    end

    private def extract_non_path_params(statement : String, params : Array(Param))
      # Extract query parameters - warp::query::<T>() or .and(warp::query())
      if statement.includes?("warp::query")
        # Try to extract the type parameter for better naming
        query_match = statement.match(/warp::query(?:::<(\w+)>)?/)
        if query_match
          param_name = query_match[1]? || "query"
          params << Param.new(param_name, "", "query")
        end
      end

      # Extract JSON body parameters - warp::body::json::<T>()
      if statement.includes?("warp::body::json") || statement.includes?("warp::body::form")
        body_match = statement.match(/warp::body::(?:json|form)(?:::<(\w+)>)?/)
        if body_match
          param_name = body_match[1]? || "body"
          params << Param.new(param_name, "", "json")
        end
      end

      # Extract header parameters - warp::header::<T>("header-name") or warp::header("header-name")
      statement.scan(/warp::header(?:::<[^>]+>)?\("([^"]+)"\)/) do |match|
        if match.size > 1
          header_name = match[1]
          params << Param.new(header_name, "", "header")
        end
      end

      # Also check for .header() pattern
      statement.scan(/\.header\("([^"]+)"\)/) do |match|
        if match.size > 1
          header_name = match[1]
          params << Param.new(header_name, "", "header")
        end
      end

      # Extract cookie parameters - warp::cookie::<T>("cookie-name") or warp::cookie("cookie-name")
      statement.scan(/warp::cookie(?:::<[^>]+>)?\("([^"]+)"\)/) do |match|
        if match.size > 1
          cookie_name = match[1]
          params << Param.new(cookie_name, "", "cookie")
        end
      end

      # Also check for .cookie() pattern
      statement.scan(/\.cookie\("([^"]+)"\)/) do |match|
        if match.size > 1
          cookie_name = match[1]
          params << Param.new(cookie_name, "", "cookie")
        end
      end
    end
  end
end
