require "../../engines/crystal_engine"
require "../../../utils/url_path"

module Analyzer::Crystal
  class Kemal < CrystalEngine
    NAMESPACE_PATTERN = /^(\s*)(?:(\w+)\.)?namespace\s+["'](.+?)["']/
    MOUNT_PATTERN     = /^\s*mount\s+["'](.+?)["']\s*,\s*(\w+)/
    ROUTER_PATTERN    = /^\s*(\w+)\s*=\s*Kemal::Router\.new/
    # Compile-time macro var assignment, e.g. `{{namespace = Routes::API::V1}}`.
    # invidious sets it once, then registers 50+ routes as
    # `get "/…", {{namespace}}::Videos, :videos` — substituting it back lets
    # those routes resolve their controller and carry callees.
    MACRO_VAR_PATTERN = /\{\{\s*(\w+)\s*=\s*([A-Za-z_][\w:]*)\s*\}\}/

    @static_disabled_bases : Set(String) = Set(String).new
    @public_folders : Array(Tuple(String, String)) = [] of Tuple(String, String)
    @action_index : ActionIndex = ActionIndex.new

    def analyze
      # Apps like invidious register routes as `get "/", Routes::Misc, :home`
      # with the handler defined in a separate controller file. Build the
      # cross-file action index up front so those routes can carry callees.
      if any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
        @action_index = build_crystal_action_index(all_files)
      end
      super
      collect_public_dir_endpoints
      @result
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = mask_crystal_heredocs(File.read_lines(path))
      file_base = configured_base_for(path)
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      # Pre-scan: build mount_map (variable_name => mount_path) and resolve
      # compile-time macro variables used in controller references.
      mount_map = {} of String => String
      router_vars = Set(String).new
      macro_vars = {} of String => String

      lines.each do |line|
        if match = line.match(ROUTER_PATTERN)
          router_vars << match[1]
        end
        if match = line.match(MOUNT_PATTERN)
          mount_map[match[2]] = match[1]
        end
        if include_callee
          if match = line.match(MACRO_VAR_PATTERN)
            macro_vars[match[1]] = match[2]
          end
        end
      end

      # Main scan with namespace stack
      namespace_stack = [] of NamedTuple(prefix: String, indent: Int32, router_var: String)
      last_endpoint : Endpoint? = nil

      lines.each_with_index do |line, index|
        # Collect public folder / serve_static info (used by post-pass)
        if line.includes?("serve_static false") || line.includes?("serve_static(false)")
          @static_disabled_bases << file_base
        end

        if line.includes?("public_folder")
          begin
            split = line.split("public_folder")

            if split.size > 1
              match_data = split[1].match(/[=\(]\s*['"]?(.*?)['"]?\s*[\),]/)
              public_folder = if match_data && match_data[1]?
                                match_data[1].strip
                              else
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

        # Check for namespace open
        if match = line.match(NAMESPACE_PATTERN)
          indent = match[1].size
          router_var = match[2]? || ""
          prefix = match[3]
          namespace_stack << {prefix: prefix, indent: indent, router_var: router_var}
          next
        end

        # Check for end that closes a namespace
        unless namespace_stack.empty?
          if end_match = line.match(/^(\s*)end\b/)
            end_indent = end_match[1].size
            if end_indent == namespace_stack.last[:indent]
              namespace_stack.pop
              next
            end
          end
        end

        # Parse endpoint
        endpoint = line_to_endpoint(line)
        if !endpoint.method.empty? && valid_crystal_route_path?(endpoint.url)
          # Build full path with namespace prefixes and mount path
          route_path = endpoint.url
          full_path = route_path

          unless namespace_stack.empty?
            # Combine all namespace prefixes
            ns_prefix = ""
            namespace_stack.each do |ns|
              ns_prefix = Noir::URLPath.join(ns_prefix, ns[:prefix])
            end
            full_path = Noir::URLPath.join(ns_prefix, route_path)

            # Determine router variable for mount lookup
            router_var = namespace_stack.first[:router_var]
            if !router_var.empty? && mount_map.has_key?(router_var)
              full_path = Noir::URLPath.join(mount_map[router_var], full_path)
            end
          end

          endpoint.url = full_path
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          attach_route_callees(endpoint, lines, index, path, macro_vars) if include_callee
          endpoints << endpoint
          last_endpoint = endpoint
        end

        # Parse params
        param = line_to_param(line)
        unless param.name.empty?
          if le = last_endpoint
            unless le.method.empty?
              le.push_param(param)
            end
          end
        end
      end

      endpoints
    end

    private def attach_route_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String, macro_vars : Hash(String, String))
      # Preferred source: the inline `do … end` route block.
      if route_body = extract_crystal_do_block(lines, index)
        body, body_start_line = route_body
        callees = Noir::CrystalCalleeExtractor.callees_for_body(body, path, body_start_line)
        attach_crystal_callees(endpoint, callees)
        return
      end

      # Fallback: `get "/path", Controller, :action` dispatches to a handler
      # in another file — resolve it through the cross-file action index.
      if target = extract_route_target(substitute_macro_vars(lines[index], macro_vars))
        controller, action = target
        if callees = resolve_action_callees(@action_index, controller, action, configured_base_for(path))
          attach_crystal_callees(endpoint, callees)
        end
      end
    end

    private def extract_route_target(line : String) : Tuple(String, String)?
      if match = line.match(/\b(?:get|post|put|delete|patch|head|options|ws)\s+['"][^'"]+['"]\s*,\s*([A-Za-z_]\w*(?:::[A-Za-z_]\w*)*)\s*,\s*:(\w+)/)
        {match[1], match[2]}
      end
    end

    private def substitute_macro_vars(line : String, macro_vars : Hash(String, String)) : String
      return line if macro_vars.empty? || !line.includes?("{{")
      line.gsub(/\{\{\s*(\w+)\s*\}\}/) { |whole| macro_vars[$~[1]]? || whole }
    end

    private def collect_public_dir_endpoints
      base_paths.each do |base|
        next if @static_disabled_bases.includes?(base)
        get_public_files(base).each do |file|
          if file =~ /\/public\/(.*)/
            relative_path = $1
            @result << Endpoint.new("/#{relative_path}", "GET")
          end
        end
      end

      @public_folders.each do |base, folder|
        next if @static_disabled_bases.includes?(base)
        get_public_dir_files(base, folder).each do |file|
          if folder.includes?("/")
            folder_path = folder.ends_with?("/") ? folder : "#{folder}/"
            if file.starts_with?(folder_path)
              relative_path = file.sub(folder_path, "")
              @result << Endpoint.new("/#{relative_path}", "GET")
            else
              folder_name = folder.split("/").last
              if file =~ /\/#{folder_name}\/(.*)/
                relative_path = $1
                @result << Endpoint.new("/#{relative_path}", "GET")
              end
            end
          elsif file =~ /\/#{folder}\/(.*)/
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

      if content.includes? "env.params.query["
        param = content.split("env.params.query[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "query")
      end

      if content.includes? "env.params.json["
        param = content.split("env.params.json[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "json")
      end

      if content.includes? "env.params.body["
        param = content.split("env.params.body[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "form")
      end

      if content.includes? "env.request.headers["
        param = content.split("env.request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      if content.includes? "env.request.cookies["
        param = content.split("env.request.cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      if content.includes? "cookies.get_raw("
        param = content.split("cookies.get_raw(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      Param.new("", "", "")
    end

    def line_to_endpoint(content : String) : Endpoint
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

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
