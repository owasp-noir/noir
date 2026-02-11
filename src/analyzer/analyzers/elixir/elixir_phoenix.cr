require "../../../models/analyzer"

module Analyzer::Elixir
  class Phoenix < Analyzer
    # Store mapping of route -> controller/action for parameter extraction
    @route_map : Hash(String, ControllerAction) = Hash(String, ControllerAction).new

    struct ControllerAction
      property controller : String
      property action : String

      def initialize(@controller : String, @action : String)
      end
    end

    def analyze
      # Source Analysis - First pass: collect routes
      channel = Channel(String).new

      begin
        populate_channel_with_files(channel)

        WaitGroup.wait do |wg|
          @options["concurrency"].to_s.to_i.times do
            wg.spawn do
              loop do
                begin
                  path = channel.receive?
                  break if path.nil?
                  next if File.directory?(path)
                  if File.exists?(path) && File.extname(path) == ".ex"
                    File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
                      file.each_line.with_index do |line, index|
                        endpoints = line_to_endpoint(line, path)
                        endpoints.each do |endpoint|
                          if endpoint.method != ""
                            details = Details.new(PathInfo.new(path, index + 1))
                            endpoint.details = details
                            @result << endpoint
                          end
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

      # Second pass: extract parameters from controller files
      extract_controller_params

      @result
    end

    def extract_controller_params
      # Find all controller files and extract parameters
      controller_files = Dir.glob(File.join(escape_glob_path(@base_path), "**", "*_controller.ex"))

      controller_files.each do |controller_path|
        next unless File.exists?(controller_path)

        begin
          content = File.read(controller_path, encoding: "utf-8", invalid: :skip)
          controller_name = File.basename(controller_path, ".ex")

          # Extract parameters from each action in the controller
          extract_params_from_controller(content, controller_name, controller_path)
        rescue e
          logger.debug "Error reading controller file #{controller_path}: #{e}"
        end
      end
    end

    def extract_params_from_controller(content : String, controller_name : String, controller_path : String)
      lines = content.lines

      # Find all function definitions and extract parameters
      lines.each_with_index do |line, index|
        # Match public function definitions only: def action_name(conn, _params) do
        # Exclude private functions (defp)
        next if line.match(/^\s*defp\s/)
        if match = line.match(/^\s*def\s+(\w+)\(conn,/)
          action_name = match[1]

          # Find the matching endpoints for this controller and action
          @result.each do |endpoint|
            # Match based on route_map if available, or try to match by convention
            if should_extract_params_for_endpoint?(endpoint, controller_name, action_name)
              # Find the end of the function block
              block_end = find_function_end(lines, index)
              next if block_end == -1

              # Extract parameters from the function block
              params = extract_params_from_function_block(lines, index, block_end, endpoint.method)
              params.each { |param| endpoint.push_param(param) }
            end
          end
        end
      end
    end

    def should_extract_params_for_endpoint?(endpoint : Endpoint, controller_name : String, action_name : String) : Bool
      # Check if the endpoint's route_map entry matches this controller/action
      route_key = "#{endpoint.method}::#{endpoint.url}"
      if @route_map.has_key?(route_key)
        mapping = @route_map[route_key]
        # Normalize both controller names and check for exact match
        normalized_controller = controller_name.downcase.gsub("_controller", "")
        normalized_mapping = mapping.controller.downcase.gsub("controller", "")
        return normalized_controller == normalized_mapping && mapping.action == action_name
      end

      # Fallback: try to match by conventional naming
      # For example, resources routes: GET /posts -> PostController.index
      false
    end

    def find_function_end(lines : Array(String), start_index : Int32) : Int32
      # Find the matching "end" for the function starting with "def"
      return -1 if start_index >= lines.size

      depth = 1
      (start_index + 1...lines.size).each do |i|
        line = lines[i].strip

        # Count keywords that increase depth (excluding 'fn' which has different end syntax)
        depth += line.scan(/\b(do|def|defp|case|cond|if|unless)\b/).size

        # Count "end" keywords that decrease depth
        depth -= line.scan(/\bend\b/).size

        return i if depth == 0
      end

      -1
    end

    def extract_params_from_function_block(lines : Array(String), start_index : Int32, end_index : Int32, method : String) : Array(Param)
      params = Array(Param).new
      seen_params = Set(String).new # Track seen params for O(1) lookup

      # Extract parameters from the function block content
      (start_index..end_index).each do |i|
        line = lines[i]

        # Extract query parameters (conn.query_params["param"])
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

        # Extract body parameters (conn.body_params["param"])
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

    def line_to_endpoint(line : String, file_path : String) : Array(Endpoint)
      endpoints = Array(Endpoint).new

      # Standard HTTP methods - extract controller and action info
      line.scan(/get\s+['"](.+?)['"]\s*,\s*(\w+),\s*:(\w+)/) do |match|
        endpoint = Endpoint.new("#{match[1]}", "GET")
        controller = match[2]
        action = match[3]
        @route_map["GET::#{match[1]}"] = ControllerAction.new(controller, action)
        endpoints << endpoint
      end

      line.scan(/post\s+['"](.+?)['"]\s*,\s*(\w+),\s*:(\w+)/) do |match|
        endpoint = Endpoint.new("#{match[1]}", "POST")
        controller = match[2]
        action = match[3]
        @route_map["POST::#{match[1]}"] = ControllerAction.new(controller, action)
        endpoints << endpoint
      end

      line.scan(/patch\s+['"](.+?)['"]\s*,\s*(\w+),\s*:(\w+)/) do |match|
        endpoint = Endpoint.new("#{match[1]}", "PATCH")
        controller = match[2]
        action = match[3]
        @route_map["PATCH::#{match[1]}"] = ControllerAction.new(controller, action)
        endpoints << endpoint
      end

      line.scan(/put\s+['"](.+?)['"]\s*,\s*(\w+),\s*:(\w+)/) do |match|
        endpoint = Endpoint.new("#{match[1]}", "PUT")
        controller = match[2]
        action = match[3]
        @route_map["PUT::#{match[1]}"] = ControllerAction.new(controller, action)
        endpoints << endpoint
      end

      line.scan(/delete\s+['"](.+?)['"]\s*,\s*(\w+),\s*:(\w+)/) do |match|
        endpoint = Endpoint.new("#{match[1]}", "DELETE")
        controller = match[2]
        action = match[3]
        @route_map["DELETE::#{match[1]}"] = ControllerAction.new(controller, action)
        endpoints << endpoint
      end

      # Socket routes
      line.scan(/socket\s+['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
        tmp = Endpoint.new("#{match[1]}", "GET")
        tmp.protocol = "ws"
        endpoints << tmp
      end

      # LiveView routes
      line.scan(/live\s+['"](.+?)['"]\s*,\s*(.+?)\s*/) do |match|
        endpoints << Endpoint.new("#{match[1]}", "GET")
      end

      # Resources macro - generates standard REST routes
      if match = line.match(/resources\s+['"]([^'"]+)['"]\s*,\s*(\w+)(?:\s*,\s*only:\s*\[([^\]]+)\])?/)
        base_path = match[1]
        controller = match[2]
        only_actions = match[3]?

        if only_actions
          # Parse only: [:index, :show, :create, etc.]
          actions = only_actions.scan(/:(\w+)/).map { |m| m[1] }
        else
          # Default to all REST actions
          actions = ["index", "show", "create", "update", "delete", "new", "edit"]
        end

        actions.each do |action|
          case action
          when "index"
            endpoint = Endpoint.new(base_path, "GET")
            @route_map["GET::#{base_path}"] = ControllerAction.new(controller, "index")
            endpoints << endpoint
          when "show"
            endpoint = Endpoint.new("#{base_path}/:id", "GET")
            @route_map["GET::#{base_path}/:id"] = ControllerAction.new(controller, "show")
            endpoints << endpoint
          when "create"
            endpoint = Endpoint.new(base_path, "POST")
            @route_map["POST::#{base_path}"] = ControllerAction.new(controller, "create")
            endpoints << endpoint
          when "update"
            put_endpoint = Endpoint.new("#{base_path}/:id", "PUT")
            @route_map["PUT::#{base_path}/:id"] = ControllerAction.new(controller, "update")
            endpoints << put_endpoint

            patch_endpoint = Endpoint.new("#{base_path}/:id", "PATCH")
            @route_map["PATCH::#{base_path}/:id"] = ControllerAction.new(controller, "update")
            endpoints << patch_endpoint
          when "delete"
            endpoint = Endpoint.new("#{base_path}/:id", "DELETE")
            @route_map["DELETE::#{base_path}/:id"] = ControllerAction.new(controller, "delete")
            endpoints << endpoint
          when "new"
            endpoint = Endpoint.new("#{base_path}/new", "GET")
            @route_map["GET::#{base_path}/new"] = ControllerAction.new(controller, "new")
            endpoints << endpoint
          when "edit"
            endpoint = Endpoint.new("#{base_path}/:id/edit", "GET")
            @route_map["GET::#{base_path}/:id/edit"] = ControllerAction.new(controller, "edit")
            endpoints << endpoint
          end
        end
      end

      endpoints
    end
  end
end
