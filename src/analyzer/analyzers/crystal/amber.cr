require "../../engines/crystal_engine"

module Analyzer::Crystal
  class Amber < CrystalEngine
    # `routes :web, "/admin" do … end` — the optional second argument is a
    # path scope that prefixes every route declared inside the block.
    ROUTES_SCOPE_PATTERN = /^(\s*)routes\s+:\w+(?:\s*,\s*["']([^"']*)["'])?\s+do\b/
    # `namespace "/admin" do … end` — Amber's DSL scope macro.
    NAMESPACE_PATTERN = /^(\s*)namespace\s+["']([^"']*)["']\s+do\b/
    # `resources "/posts", PostController[, only: …][, except: …]`.
    RESOURCES_PATTERN = /^\s*resources\s+["']([^"']+)["']\s*,\s*([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\s*(.*)$/

    # Amber's `resources` macro expands to the seven RESTful routes below
    # (update is registered for both PUT and PATCH). `resource` (singular)
    # shares the same action set; the `:id` segment is auto-detected as a
    # path param downstream, so we only emit the verb + URL + action here.
    RESOURCE_ROUTES = [
      {"GET", "", :index},
      {"GET", "/new", :new},
      {"POST", "", :create},
      {"GET", "/:id", :show},
      {"GET", "/:id/edit", :edit},
      {"PUT", "/:id", :update},
      {"PATCH", "/:id", :update},
      {"DELETE", "/:id", :destroy},
    ]

    @static_disabled_bases : Set(String) = Set(String).new
    @public_folders : Array(Tuple(String, String)) = [] of Tuple(String, String)

    def analyze
      super
      collect_public_dir_endpoints
      @result
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = [] of String
      file_base = configured_base_for(path)

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line do |line|
          lines << line
        end
      end
      lines = mask_crystal_heredocs(lines)

      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      actions = include_callee ? collect_controller_actions(lines, path) : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)).new
      last_endpoint = Endpoint.new("", "")

      # Stack of `{prefix, indent}` for open `routes "/scope"`/`namespace`
      # blocks. The path scope is the concatenation of every open prefix.
      scope_stack = [] of NamedTuple(prefix: String, indent: Int32)

      lines.each_with_index do |line, index|
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line)

        # Open a scope block (routes-with-scope or namespace).
        if match = stripped.match(ROUTES_SCOPE_PATTERN)
          scope_stack << {prefix: match[2]? || "", indent: match[1].size}
          next
        end
        if match = stripped.match(NAMESPACE_PATTERN)
          scope_stack << {prefix: match[2], indent: match[1].size}
          next
        end

        # Close the innermost scope when an `end` lines up with its indent.
        unless scope_stack.empty?
          if end_match = stripped.match(/^(\s*)end\b/)
            if end_match[1].size == scope_stack.last[:indent]
              scope_stack.pop
              next
            end
          end
        end

        scope_prefix = scope_stack.reduce("") { |acc, ns| Noir::URLPath.join(acc, ns[:prefix]) }

        # `resources`/`resource` macros expand to several RESTful routes.
        if match = stripped.match(RESOURCES_PATTERN)
          expand_resources(match[1], match[2], match[3], scope_prefix, path, index, actions, include_callee).each do |ep|
            endpoints << ep
            last_endpoint = ep
          end
          next
        end

        endpoint = line_to_endpoint(line)
        if !endpoint.method.empty? && valid_crystal_route_path?(endpoint.url)
          endpoint.url = Noir::URLPath.join(scope_prefix, endpoint.url) unless scope_prefix.empty?
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          attach_route_callees(endpoint, line, actions) if include_callee
          endpoints << endpoint
          last_endpoint = endpoint
        end

        param = line_to_param(line)
        unless param.name.empty?
          unless last_endpoint.method.empty?
            last_endpoint.push_param(param)
          end
        end

        if line.includes?("serve_static false") || line.includes?("serve_static(false)")
          @static_disabled_bases << file_base
        end

        if line.includes?("public_folder")
          begin
            split = line.split("public_folder")

            if split.size > 1
              # Extract path more carefully handling quotes and spaces
              match_data = split[1].match(/[=\(]\s*['"]?(.*?)['"]?\s*[\),]/)
              public_folder = if match_data && match_data[1]?
                                match_data[1].strip
                              else
                                # Fallback to the previous approach
                                split[1].gsub("(", "").gsub(")", "").gsub(" ", "").gsub("\"", "").gsub("'", "")
                              end

              unless public_folder.empty?
                entry = {file_base, public_folder}
                @public_folders << entry unless @public_folders.includes?(entry)
              end
            end
          rescue
          end
        end
      end

      endpoints
    end

    private def collect_controller_actions(lines : Array(String), path : String) : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry))
      actions = Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)).new
      current_class = ""
      class_depth = 0

      lines.each_with_index do |line, index|
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line).strip
        if class_match = stripped.match(/^class\s+([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\b/)
          current_class = class_match[1]
          class_depth = 1
          next
        end

        next if current_class.empty?
        if stripped == "end" || stripped.starts_with?("end ")
          class_depth -= 1
          if class_depth <= 0
            current_class = ""
            class_depth = 0
          end
          next
        end

        if class_depth == 1 && (def_match = stripped.match(/^(?:(?:private|protected)\s+)?def\s+([A-Za-z_]\w*[!?=]?)/))
          method_body = extract_crystal_def_block(lines, index)
          if method_body
            body, body_start_line = method_body
            callees = Noir::CrystalCalleeExtractor.callees_for_body(body, path, body_start_line)
            actions[controller_action_key(current_class, def_match[1])] = callees
          end
        end

        class_depth += crystal_do_block_open_delta(stripped)
      end

      actions
    end

    private def attach_route_callees(endpoint : Endpoint,
                                     line : String,
                                     actions : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)))
      route_target = extract_route_target(line)
      return unless route_target

      controller, action = route_target
      if callees = actions[controller_action_key(controller, action)]?
        attach_crystal_callees(endpoint, callees)
      end
    end

    private def extract_route_target(line : String) : Tuple(String, String)?
      if match = line.match(/\b(?:get|post|put|delete|patch|head|options|ws)\s+['"][^'"]+['"]\s*,\s*([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\s*,\s*:(\w+)/)
        {match[1], match[2]}
      end
    end

    # Expand a `resources "/posts", PostController` macro into its RESTful
    # routes, prefixing each with the active scope and wiring callees from
    # the matching controller action when available (same-file controllers).
    private def expand_resources(resource : String,
                                 controller : String,
                                 opts : String,
                                 scope_prefix : String,
                                 path : String,
                                 index : Int32,
                                 actions : Hash(String, Array(Noir::CrystalCalleeExtractor::Entry)),
                                 include_callee : Bool) : Array(Endpoint)
      result = [] of Endpoint
      # `resources "/posts"` and `resources "posts"` both map to `/posts`.
      base = resource.strip.strip("/")
      return result if base.empty?

      allowed = resource_actions(opts)
      base_path = Noir::URLPath.join(scope_prefix, "/#{base}")

      RESOURCE_ROUTES.each do |method, suffix, action|
        next unless allowed.includes?(action)
        url = suffix.empty? ? base_path : Noir::URLPath.join(base_path, suffix)
        endpoint = Endpoint.new(url, method)
        endpoint.details = Details.new(PathInfo.new(path, index + 1))
        if include_callee
          if callees = actions[controller_action_key(controller, action.to_s)]?
            attach_crystal_callees(endpoint, callees)
          end
        end
        result << endpoint
      end

      result
    end

    # Resolve the active resource actions, honouring `only:`/`except:`.
    private def resource_actions(opts : String) : Array(Symbol)
      all = [:index, :new, :create, :show, :edit, :update, :destroy]
      if match = opts.match(/\bonly:\s*\[([^\]]*)\]/)
        names = match[1].scan(/:(\w+)/).map { |m| m[1] }
        return all.select { |action| names.includes?(action.to_s) }
      end
      if match = opts.match(/\bexcept:\s*\[([^\]]*)\]/)
        names = match[1].scan(/:(\w+)/).map { |m| m[1] }
        return all.reject { |action| names.includes?(action.to_s) }
      end
      all
    end

    private def controller_action_key(controller : String, action : String) : String
      "#{controller}##{action}"
    end

    private def collect_public_dir_endpoints
      # Process public folder files
      base_paths.each do |base|
        next if @static_disabled_bases.includes?(base)
        get_public_files(base).each do |file|
          # Extract the path after "/public/" regardless of depth
          if file =~ /\/public\/(.*)/
            relative_path = $1
            @result << Endpoint.new("/#{relative_path}", "GET")
          end
        end
      end

      # Process other public folders
      @public_folders.each do |base, folder|
        next if @static_disabled_bases.includes?(base)
        get_public_dir_files(base, folder).each do |file|
          # Extract relative path from the custom folder
          if folder.includes?("/")
            # For absolute paths or paths with directories
            folder_path = folder.ends_with?("/") ? folder : "#{folder}/"
            if file.starts_with?(folder_path)
              relative_path = file.sub(folder_path, "")
              @result << Endpoint.new("/#{relative_path}", "GET")
            else
              # Try to find the folder component in the path
              folder_name = folder.split("/").last
              if file =~ /\/#{folder_name}\/(.*)/
                relative_path = $1
                @result << Endpoint.new("/#{relative_path}", "GET")
              end
            end
          elsif file =~ /\/#{folder}\/(.*)/
            # For simple folder names (no slashes)
            relative_path = $1
            @result << Endpoint.new("/#{relative_path}", "GET")
          end
        end
      end
    rescue e
      logger.debug e
    end

    def line_to_param(content : String) : Param
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      # Amber uses params object for accessing parameters
      if content.includes? "params["
        param = content.split("params[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "query")
      end

      # Query parameters
      if content.includes? "params.query["
        param = content.split("params.query[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "query")
      end

      # JSON parameters
      if content.includes? "params.json["
        param = content.split("params.json[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "json")
      end

      # Form parameters
      if content.includes? "params.body["
        param = content.split("params.body[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "form")
      end

      # Headers
      if content.includes? "request.headers["
        param = content.split("request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      # Cookies
      if content.includes? "request.cookies["
        param = content.split("request.cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      # Context headers access
      if content.includes? "context.request.headers["
        param = content.split("context.request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(content : String) : Endpoint
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      # Amber route definitions with controller and action
      content.scan(/(?:^|[^.\w])get\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*\w+,\s*:(\w+)/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "GET")
        end
      end

      content.scan(/(?:^|[^.\w])post\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*\w+,\s*:(\w+)/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "POST")
        end
      end

      content.scan(/(?:^|[^.\w])put\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*\w+,\s*:(\w+)/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "PUT")
        end
      end

      content.scan(/(?:^|[^.\w])delete\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*\w+,\s*:(\w+)/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "DELETE")
        end
      end

      content.scan(/(?:^|[^.\w])patch\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*\w+,\s*:(\w+)/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "PATCH")
        end
      end

      content.scan(/(?:^|[^.\w])head\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*\w+,\s*:(\w+)/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "HEAD")
        end
      end

      content.scan(/(?:^|[^.\w])options\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*\w+,\s*:(\w+)/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "OPTIONS")
        end
      end

      # WebSocket support in Amber
      content.scan(/(?:^|[^.\w])ws\s*(?:\(\s*)?['"](.+?)['"]\s*,\s*\w+,\s*:(\w+)/) do |match|
        if match.size > 1
          endpoint = Endpoint.new(normalize_crystal_interpolation(match[1]), "GET")
          endpoint.protocol = "ws"
          return endpoint
        end
      end

      # Also support simple route definitions without controller (fallback)
      content.scan(/(?:^|[^.\w])get\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "GET")
        end
      end

      content.scan(/(?:^|[^.\w])post\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "POST")
        end
      end

      content.scan(/(?:^|[^.\w])put\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "PUT")
        end
      end

      content.scan(/(?:^|[^.\w])delete\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "DELETE")
        end
      end

      content.scan(/(?:^|[^.\w])patch\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "PATCH")
        end
      end

      content.scan(/(?:^|[^.\w])head\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "HEAD")
        end
      end

      content.scan(/(?:^|[^.\w])options\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "OPTIONS")
        end
      end

      # WebSocket support in Amber
      content.scan(/(?:^|[^.\w])ws\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          endpoint = Endpoint.new(normalize_crystal_interpolation(match[1]), "GET")
          endpoint.protocol = "ws"
          return endpoint
        end
      end

      Endpoint.new("", "")
    end
  end
end
