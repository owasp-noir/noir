require "../../engines/crystal_engine"

module Analyzer::Crystal
  class Lucky < CrystalEngine
    def analyze
      collect_public_dir_endpoints
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = [] of String

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        file.each_line do |line|
          lines << line
        end
      end
      lines = mask_crystal_heredocs(lines)

      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      last_endpoint = Endpoint.new("", "")

      # Lucky's `param name : Type` macro declares a query parameter at the
      # class level, above the route block. Buffer declarations and flush
      # them onto the next route; reset at each class boundary so a guide
      # file with several example actions doesn't cross-attach params.
      pending_params = [] of Param
      # Track the enclosing action class so `action`/`nested_route` (which
      # carry no path) can infer their route from the class name.
      current_class = ""

      lines.each_with_index do |line, index|
        stripped = Noir::CrystalCalleeExtractor.strip_comment(line)

        if class_match = stripped.match(/^\s*(?:abstract\s+)?class\s+([A-Z]\w*(?:::[A-Z]\w*)*)/)
          current_class = class_match[1]
          pending_params.clear
        elsif stripped.match(/^\s*(?:abstract\s+)?class\b/)
          current_class = ""
          pending_params.clear
        end

        if decl = lucky_param_declaration(stripped)
          pending_params << decl
        end

        # `action do … end` / `nested_route do … end` infer the verb and
        # path from the action class name (Lucky's RouteInferrer). This is
        # the resourceful style real apps use instead of explicit `get "/…"`.
        if inferred = infer_lucky_action_route(stripped, current_class)
          method, url = inferred
          endpoint = Endpoint.new(url, method)
          endpoint.details = Details.new(PathInfo.new(path, index + 1))
          pending_params.each { |p| endpoint.push_param(p) }
          pending_params.clear
          attach_route_callees(endpoint, lines, index, path) if include_callee
          endpoints << endpoint
          last_endpoint = endpoint
          next
        end

        endpoint = line_to_endpoint(line)
        if !endpoint.method.empty? && valid_crystal_route_path?(endpoint.url)
          details = Details.new(PathInfo.new(path, index + 1))
          endpoint.details = details
          pending_params.each { |p| endpoint.push_param(p) }
          pending_params.clear
          attach_route_callees(endpoint, lines, index, path) if include_callee
          endpoints << endpoint
          last_endpoint = endpoint
        end

        param = line_to_param(line)
        unless param.name.empty?
          unless last_endpoint.method.empty?
            last_endpoint.push_param(param)
          end
        end
      end

      endpoints
    end

    # `param name : Type` / `param name : Type = default` — Lucky's query
    # parameter declaration macro. Requires the `name :` shape so prose such
    # as "the param to determine the page" never matches.
    private def lucky_param_declaration(content : String) : Param?
      if match = content.match(/^\s*param\s+(\w+)\s*:/)
        Param.new(match[1], "", "query")
      end
    end

    RESOURCEFUL_ACTIONS = %w[index show new create edit update delete]

    # When a line opens a `route do` / `action do` / `nested_route do` block
    # inside an action class, infer the route the way Lucky's `RouteInferrer`
    # does: split the class name, the last piece is the resourceful action,
    # the piece before it is the resource. Lucky exposes the inference under
    # both `route` and `action` (real apps use either); `nested_route`
    # additionally folds in the parent as `/parent/:parent_id`. The leading
    # `route\b` won't match `routes`/`route_prefix`/`route_style`, and a
    # non-resourceful class name infers nothing. Returns `{method, url}`.
    private def infer_lucky_action_route(content : String, current_class : String) : Tuple(String, String)?
      return if current_class.empty?
      match = content.match(/^\s*(action|nested_route|route)\b.*\bdo\b/)
      return unless match
      nested = match[1] == "nested_route"

      pieces = current_class.split("::").map(&.underscore)
      return if pieces.size < 2

      action_name = pieces.last
      return unless RESOURCEFUL_ACTIONS.includes?(action_name)
      resource = pieces[-2]
      return if nested && pieces.size < 3
      parent = nested ? pieces[-3] : ""

      method = case action_name
               when "delete" then "DELETE"
               when "create" then "POST"
               when "update" then "PUT"
               else               "GET"
               end

      namespace_pieces = pieces.reject { |p| p == action_name || p == resource }
      namespace_pieces = namespace_pieces.reject { |p| p == parent } if nested
      parent_pieces = nested ? [parent, ":#{lucky_singularize(parent)}_id"] : [] of String

      resource_pieces = case action_name
                        when "index", "create" then [resource]
                        when "new"             then [resource, "new"]
                        when "edit"            then [resource, ":#{lucky_singularize(resource)}_id", "edit"]
                        else # show, update, delete
                          [resource, ":#{lucky_singularize(resource)}_id"]
                        end

      url = "/" + (namespace_pieces + parent_pieces + resource_pieces).reject(&.empty?).join("/")
      {method, url}
    end

    # Minimal inflector for the `:resource_id` path-param name. Lucky uses
    # Wordsmith; these rules cover the regular plurals real resources use.
    private def lucky_singularize(word : String) : String
      return word if word.empty?
      if word.ends_with?("ies")
        "#{word[0..-4]}y"
      elsif word.ends_with?("ses") || word.ends_with?("xes") || word.ends_with?("zes") ||
            word.ends_with?("ches") || word.ends_with?("shes")
        word[0..-3]
      elsif word.ends_with?("s") && !word.ends_with?("ss")
        word[0..-2]
      else
        word
      end
    end

    private def attach_route_callees(endpoint : Endpoint, lines : Array(String), index : Int32, path : String)
      route_body = extract_crystal_do_block(lines, index)
      return unless route_body

      body, body_start_line = route_body
      callees = Noir::CrystalCalleeExtractor.callees_for_body(body, path, body_start_line)
      attach_crystal_callees(endpoint, callees)
    end

    private def collect_public_dir_endpoints
      # `get_public_files` scopes to `public/` directories that sit
      # next to a `shard.yml`, so files in unrelated `*/public/`
      # subtrees (e.g. a built docs site at `docs/public/`) no
      # longer leak in as fake Lucky endpoints.
      each_public_file do |file|
        # Extract the path after "/public/" regardless of depth
        if file =~ /\/public\/(.*)/
          relative_path = $1
          @result << Endpoint.new("/#{relative_path}", "GET")
        end
      end
    rescue e
      logger.debug e
    end

    def line_to_param(content : String) : Param
      content = Noir::CrystalCalleeExtractor.strip_comment(content)

      if content.includes? "params.from_query[\""
        param = content.split("params.from_query[\"")[1].split("\"]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "query")
      end

      if content.includes? "params.from_json[\""
        param = content.split("params.from_json[\"")[1].split("\"]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "json")
      end

      if content.includes? "params.from_form_data[\""
        param = content.split("params.from_form_data[\"")[1].split("\"]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "form")
      end

      if content.includes? "params.get("
        param = content.split("params.get(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param.gsub(":", ""), "", "query")
      end

      if content.includes? "request.headers["
        param = content.split("request.headers[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "header")
      end

      if content.includes? "cookies.get("
        param = content.split("cookies.get(")[1].split(")")[0].gsub("\"", "").gsub("'", "")
        return Param.new(param, "", "cookie")
      end

      if content.includes? "cookies["
        param = content.split("cookies[")[1].split("]")[0].gsub("\"", "").gsub("'", "")
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

      content.scan(/(?:^|[^.\w])trace\s*(?:\(\s*)?['"](.+?)['"]/) do |match|
        if match.size > 1
          return Endpoint.new(normalize_crystal_interpolation(match[1]), "TRACE")
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
