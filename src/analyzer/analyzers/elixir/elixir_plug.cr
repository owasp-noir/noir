require "../../engines/elixir_engine"

module Analyzer::Elixir
  class Plug < ElixirEngine
    def analyze_file(path : String) : Array(Endpoint)
      ext = File.extname(path)
      return [] of Endpoint unless ext == ".ex" || ext == ".exs"

      endpoints = [] of Endpoint
      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        content = file.gets_to_end
        analyze_content(content, path).each do |endpoint|
          endpoints << endpoint if endpoint.method != ""
        end
      end
      endpoints
    end

    def analyze_content(content : String, file_path : String) : Array(Endpoint)
      endpoints = Array(Endpoint).new
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # Find all route blocks and extract params
      lines = content.lines
      lines.each_with_index do |line, index|
        line_endpoints = line_to_endpoint(line.strip)
        line_endpoints.each do |endpoint|
          if endpoint.method != ""
            details = Details.new(PathInfo.new(file_path, index + 1))
            endpoint.details = details

            block_end = find_block_end(lines, index)

            params = extract_params_from_block(lines, index, endpoint.method, block_end)
            params.each { |param| endpoint.push_param(param) }

            attach_callees_from_block(endpoint, lines, index, block_end, file_path) if include_callee

            endpoints << endpoint
          end
        end
      end

      endpoints
    end

    def extract_params_from_block(lines : Array(String), start_index : Int32, method : String, block_end : Int32? = nil) : Array(Param)
      params = Array(Param).new
      seen_params = Set(String).new # Track seen params for O(1) lookup

      # Find the end of the current route block (find matching "end")
      end_index = block_end || find_block_end(lines, start_index)
      return params if end_index == -1

      # Extract parameters from the block content
      (start_index..end_index).each do |i|
        line = lines[i]

        # Extract query parameters (conn.query_params["param"] or conn.params["param"] for GET)
        line.scan(/conn\.query_params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "query:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "query")
            seen_params << param_key
          end
        end

        # Extract params (could be query for GET or form for POST/PUT/PATCH)
        line.scan(/conn\.params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_type = (method == "GET") ? "query" : "form"
          param_key = "#{param_type}:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", param_type)
            seen_params << param_key
          end
        end

        # Extract body parameters (conn.body_params["param"] for POST/PUT/PATCH)
        line.scan(/conn\.body_params\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "form:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "form")
            seen_params << param_key
          end
        end

        # Extract header parameters (get_req_header(conn, "header-name"))
        line.scan(/get_req_header\(conn,\s*["']([^"']+)["']\)/) do |match|
          param_name = match[1]
          param_key = "header:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "header")
            seen_params << param_key
          end
        end

        # Extract cookie parameters (conn.cookies["cookie_name"])
        line.scan(/conn\.cookies\[["']([^"']+)["']\]/) do |match|
          param_name = match[1]
          param_key = "cookie:#{param_name}"
          unless seen_params.includes?(param_key)
            params << Param.new(param_name, "", "cookie")
            seen_params << param_key
          end
        end
      end

      params
    end

    private def attach_callees_from_block(endpoint : Endpoint,
                                          lines : Array(String),
                                          start_index : Int32,
                                          block_end : Int32?,
                                          file_path : String)
      return unless block_end
      return if block_end == -1 || block_end <= start_index

      body_lines = lines[(start_index + 1)...block_end]
      return if body_lines.empty?

      callees = Noir::ElixirCalleeExtractor.callees_for_lines(body_lines, file_path, start_index + 2)
      attach_elixir_callees(endpoint, callees)
    end

    def find_block_end(lines : Array(String), start_index : Int32) : Int32
      # Find the matching "end" for the route block starting with "do"
      return -1 if start_index >= lines.size

      # Check if the line has "do" keyword
      return -1 unless lines[start_index].includes?("do")

      depth = 1
      (start_index + 1...lines.size).each do |i|
        line = lines[i].strip

        # Count "do" keywords that increase depth
        depth += line.scan(/\bdo\b/).size

        # Count "end" keywords that decrease depth
        depth -= line.scan(/\bend\b/).size

        return i if depth == 0
      end

      -1
    end

    def line_to_endpoint(line : String) : Array(Endpoint)
      endpoints = Array(Endpoint).new

      # Match Plug.Router style route definitions
      # get "/path", do: ...
      line.scan(/get\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "GET")
      end

      line.scan(/post\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "POST")
      end

      line.scan(/put\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "PUT")
      end

      line.scan(/patch\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "PATCH")
      end

      line.scan(/delete\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "DELETE")
      end

      line.scan(/head\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "HEAD")
      end

      line.scan(/options\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "OPTIONS")
      end

      # Match forward statements: forward "/api", SomeModule
      line.scan(/forward\s+["\']([^"\']+)["\']/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "FORWARD")
      end

      # Match match statements with method patterns
      # match "/path", via: [:get, :post]
      if via_match = line.match(/match\s+["\']([^"\']+)["\'][^:]*via:\s*\[([^\]]+)\]/)
        path = via_match[1]
        methods_str = via_match[2]
        methods_str.scan(/:(\w+)/) do |method_match|
          endpoints << Endpoint.new(path, method_match[1].upcase)
        end
      end

      # Match simple match statements (defaults to GET)
      line.scan(/match\s+["\']([^"\']+)["\']/) do |match|
        # Only add if we didn't already match a via: pattern above
        unless line.includes?("via:")
          endpoints << Endpoint.new("#{match[1]}", "GET")
        end
      end

      endpoints
    end
  end
end
