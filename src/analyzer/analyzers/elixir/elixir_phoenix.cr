require "../../../models/analyzer"
require "../../../models/endpoint" # Assuming Param model might be part of or used by Endpoint
require "regex" # Ensure Regex is available

module Analyzer::Elixir
  class Phoenix < Analyzer
    # Helper structure for Param if not already defined globally or in Endpoint
    # struct Param
    #   property name : String
    #   property type : String # "query", "header", "cookie"
    #   property value : String? # Optional: if a default value is found
    #
    #   def initialize(@name, @type, @value = nil)
    #   end
    # end

    def analyze
      channel = Channel(Tuple(String, Array(String))).new # Tuple of file_path and all_lines

      begin
        spawn do
          Dir.glob("#{@base_path}/**/*.ex") do |file_path| # Only .ex files
            next if File.directory?(file_path)
            if File.exists?(file_path)
              all_lines = File.read_lines(file_path, encoding: "utf-8", invalid: :skip)
              channel.send({file_path, all_lines})
            end
          end
          channel.close
        end

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                received = channel.receive?
                break if received.nil?
                file_path, all_lines = received.as(Tuple(String, Array(String)))

                all_lines.each_with_index do |line, index|
                  endpoints = line_to_endpoint(line, file_path, all_lines, index, @options)
                  endpoints.each do |endpoint|
                    if endpoint.method != "" && !endpoint.path.empty?
                      @result << endpoint
                    end
                  end
                end
              rescue e # Catch errors per file processing
                logger.debug "Error processing file #{file_path}: #{e}"
              end
            end
          end
        end
      rescue e
        logger.debug "Error in analyzer setup: #{e}"
      end
      @result
    end

    # Define REGEX constants for clarity
    # Matches: get "/path", MyApp.MyController, :action_name or get "/path", MyApp.MyController, action_name
    ROUTE_REGEX = Regex.new("(get|post|put|patch|delete|options|head|connect|trace)\s+['"](.+?)['"]\s*,\s*([a-zA-Z0-9_.:]+Controller)\s*,\s*:(?:atom:)?([a-zA-Z_][a-zA-Z0-9_!?]*)", Regex::Options::IGNORE_CASE)

    # Matches: def action_name(conn, params_arg) do | def action_name(conn) do
    ACTION_DEF_REGEX_PREFIX = "def\s+"
    ACTION_DEF_REGEX_SUFFIX = "\s*\(([^)]*)\)\s*do"

    # Matches: %{"id" => id_param}
    PARAMS_MAP_REGEX = Regex.new("%\{\s*([^}]*?)\s*\}")
    PARAM_KEY_REGEX = Regex.new("['"](.+?)['"]\s*=>")

    # Matches: get_req_header(conn, "header-name") or Plug.Conn.get_req_header(conn, "header-name") or conn.get_req_header("header-name")
    HEADER_REGEX = Regex.new("(?:Plug\.Conn\.)?get_req_header\s*\(\s*(?:conn\s*,)?\s*['"](.+?)['"]\s*\)")
    CONN_HEADER_REGEX = Regex.new("conn\.get_req_header\s*\(\s*['"](.+?)['"]\s*\)")


    # Matches: conn.req_cookies["cookie-name"] or Map.get(conn.req_cookies, "cookie-name")
    COOKIE_REGEX = Regex.new("conn\.req_cookies\[\s*['"](.+?)['"]\s*\]|Map\.get\(\s*conn\.req_cookies\s*,\s*['"](.+?)['"]\s*\)")

    def line_to_endpoint(line : String, file_path : String, all_lines : Array(String), route_line_index : Int, options : Hash(String,String)) : Array(Endpoint)
      endpoints = Array(Endpoint).new

      if route_match = ROUTE_REGEX.match(line)
        http_method = route_match[1].upcase
        path = route_match[2]
        # controller_module_name = route_match[3] # Not directly used yet, but good to have
        action_name = route_match[4]

        endpoint = Endpoint.new(path, http_method)
        endpoint.details = Details.new(PathInfo.new(file_path, route_line_index + 1))

        # Try to find the action definition in the current file
        action_def_regex_str = ACTION_DEF_REGEX_PREFIX + Regex.escape(action_name) + ACTION_DEF_REGEX_SUFFIX
        action_def_regex = Regex.new(action_def_regex_str)

        action_body_lines = Array(String).new
        action_def_line_number = -1
        in_action_body = false
        indentation_level = -1

        all_lines.each_with_index do |current_file_line, current_file_line_idx|
          if !in_action_body
            if action_match = action_def_regex.match(current_file_line)
              action_def_line_number = current_file_line_idx + 1
              in_action_body = true

              # Try to determine indentation for 'end'
              # This is a simple heuristic. A proper parser would be better.
              leading_spaces = current_file_line.match(/^(\s*)/)
              indentation_level = leading_spaces ? leading_spaces.not_nil![1].size : 0

              # Parse parameters from signature: action_match[1] contains args like "conn, %{"id" => id}"
              args_str = action_match[1]
              if args_str.includes?(",")
                params_part_str = args_str.split(',', 2)[1]?.to_s.strip
                if params_map_match = PARAMS_MAP_REGEX.match(params_part_str)
                  map_content = params_map_match[1]
                  map_content.scan(PARAM_KEY_REGEX) do |param_key_match|
                    param_name = param_key_match[1]
                    new_param = Param.new(param_name, "", "query")
                    endpoint.push_param(new_param)
                  end
                end
              end
              next # Move to next line to start capturing body
            end
          end

          if in_action_body
            # Check for end of function block
            # Simple check: "end" at same or less indentation. Robust parsing is hard with regex.
            current_indent = (current_file_line.match(/^(\s*)/) ? current_file_line.match(/^(\s*)/).not_nil![1].size : 0)
            if current_file_line.strip == "end" && current_indent <= indentation_level
              in_action_body = false
              break # Found end of action
            end

            action_body_lines << current_file_line

            # Scan for headers
            if header_match = HEADER_REGEX.match(current_file_line)
              header_name = header_match[1]
              new_param = Param.new(header_name, "", "header")
              endpoint.push_param(new_param)
            elsif conn_header_match = CONN_HEADER_REGEX.match(current_file_line)
              header_name = conn_header_match[1]
              new_param = Param.new(header_name, "", "header")
              endpoint.push_param(new_param)
            end

            # Scan for cookies
            if cookie_match = COOKIE_REGEX.match(current_file_line)
              # COOKIE_REGEX has two capture groups because of OR
              cookie_name = cookie_match[1]? || cookie_match[2]?
              if cookie_name
                new_param = Param.new(cookie_name, "", "cookie")
                endpoint.push_param(new_param)
              end
            end
          end
        end
        endpoints << endpoint
      end
      endpoints
    end
  end
end
