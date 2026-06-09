require "../../engines/ruby_engine"

module Analyzer::Ruby
  class Hanami < RubyEngine
    HANAMI_HTTP_VERBS = HTTP_VERBS + ["trace"]

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile). The verb set is fixed, so precompile the
    # per-verb route matchers once at load time.
    HANAMI_VERB_PATTERNS = HANAMI_HTTP_VERBS.map do |verb|
      {verb, /^#{verb}\s*\(?\s*['"]([^'"]*)['"](.*)$/}
    end

    struct RouteFrame
      property path, slice, action_prefix

      def initialize(@path : String = "", @slice : String? = nil, @action_prefix : String = "")
      end
    end

    record RouteEndpoint, endpoint : Endpoint, target : String?

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      framework_roots = discover_framework_roots("config/routes.rb")
      framework_roots = base_paths if framework_roots.empty?

      framework_roots.each do |framework_root|
        path = "#{framework_root}/config/routes.rb"
        next unless File.exists?(path)

        parse_routes_file(path, framework_root, include_callee)
      end

      @result
    end

    private def parse_routes_file(path : String, framework_root : String, include_callee : Bool)
      stack = [] of RouteFrame

      File.open(path, "r", encoding: "utf-8", invalid: :skip) do |file|
        hanami_logical_lines(file).each do |line, index|
          if closes_block?(line)
            stack.pop unless stack.empty?
            next
          end

          opens_block = opens_route_block?(line)
          details = Details.new(PathInfo.new(path, index + 1))

          if mounted = mount_endpoint(line, stack, details)
            @result << mounted
            next
          end

          if neutral_block?(line)
            stack << RouteFrame.new if opens_block
            next
          end

          if frame = slice_frame(line)
            stack << frame if opens_block
            next
          end

          if frame = prefix_frame(line, ["namespace", "scope"])
            stack << frame if opens_block
            next
          end

          if resource = resource_call(line)
            routes, nested_frame = expand_resource(resource, stack, details)
            routes.each { |route| attach_action_context(route.endpoint, route.target, framework_root, stack, include_callee) }
            @result.concat(routes.map(&.endpoint))
            stack << nested_frame if opens_block
            next
          end

          if route = root_endpoint(line, stack, details)
            attach_action_context(route.endpoint, route.target, framework_root, stack, include_callee)
            @result << route.endpoint
            stack << RouteFrame.new if opens_block
            next
          end

          if route = verb_endpoint(line, stack, details)
            attach_action_context(route.endpoint, route.target, framework_root, stack, include_callee)
            @result << route.endpoint
            stack << RouteFrame.new if opens_block
          end
        end
      end
    end

    # Join continuation lines so a route whose options spill onto the next
    # line is parsed as one statement. Hanami routes routinely wrap a long
    # `to:`/`as:` tail:
    #   post "/extensions/:extension_id/build",
    #        to: "extensions.builds.create"
    # Without joining, the verb line carries no `to:` so the action file is
    # never opened and all of the route's params/callees are dropped.
    # Returns {logical_line, first_line_index} pairs; comments are stripped
    # and strings preserved, mirroring the per-line parse.
    private def hanami_logical_lines(file) : Array(Tuple(String, Int32))
      result = [] of Tuple(String, Int32)
      buffer = ""
      buffer_index = 0

      file.each_line.with_index do |raw_line, index|
        line = Noir::RubyCalleeExtractor.strip_comment(raw_line, preserve_strings: true).strip
        next if line.empty?

        if buffer.empty?
          buffer = line
          buffer_index = index
        else
          buffer = "#{buffer} #{line}"
        end

        next if buffer.ends_with?(",")
        result << {buffer, buffer_index}
        buffer = ""
      end

      result << {buffer, buffer_index} unless buffer.empty?
      result
    end

    # `mount RackApp, at: "/path"` mounts a sub-app at a prefix (Sidekiq::Web,
    # a sub-router). Emit a best-effort GET at the mount prefix so the
    # mounted surface isn't invisible — same shape as the Rails analyzer.
    private def mount_endpoint(line : String, stack : Array(RouteFrame), details : Details) : Endpoint?
      return unless call = route_call(line, ["mount"])
      return unless m = call.match(/\bat:\s*['"]([^'"]+)['"]/)

      Endpoint.new(join_paths(current_path_prefix(stack), m[1]), "GET", details)
    end

    def extract_action_path(content : String, framework_root : String = @base_path) : String
      target = extract_action_target(content)
      return "" unless target

      find_action_path(target, framework_root, nil)
    end

    def scan_action_file(endpoint : Endpoint, action_path : String, include_callee : Bool = false)
      return unless File.exists?(action_path)

      lines = [] of String
      File.open(action_path, "r", encoding: "utf-8", invalid: :skip) do |file|
        lines = file.each_line.to_a
      end

      scan_action_params(endpoint, lines)
      attach_handle_callees(endpoint, action_path, lines) if include_callee
    end

    private def attach_action_context(endpoint : Endpoint, target : String?, framework_root : String,
                                      stack : Array(RouteFrame), include_callee : Bool)
      return unless target

      action_path = find_action_path(target, framework_root, current_slice(stack))
      scan_action_file(endpoint, action_path, include_callee) unless action_path.empty?
    end

    private def root_endpoint(line : String, stack : Array(RouteFrame), details : Details) : RouteEndpoint?
      return unless line.match(/^root(?:\s|\(|\{|$)/)

      endpoint = Endpoint.new(join_paths(current_path_prefix(stack), "/"), "GET", details)
      RouteEndpoint.new(endpoint, extract_action_target(line))
    end

    private def verb_endpoint(line : String, stack : Array(RouteFrame), details : Details) : RouteEndpoint?
      HANAMI_VERB_PATTERNS.each do |verb, verb_pattern|
        next unless line.starts_with?(verb)
        next if line.size > verb.size && (line[verb.size].alphanumeric? || line[verb.size] == '_')

        if m = line.match(verb_pattern)
          endpoint = Endpoint.new(join_paths(current_path_prefix(stack), normalize_route_path(m[1])), verb.upcase, details)
          return RouteEndpoint.new(endpoint, extract_action_target(m[2]))
        end
      end

      nil
    end

    private def neutral_block?(line : String) : Bool
      !!line.match(/^(?:class|module)\b/) || !!line.match(/^define\s+do\b/)
    end

    private def opens_route_block?(line : String) : Bool
      !!line.match(/\bdo\b/) && !line.match(/\bend\b/)
    end

    private def closes_block?(line : String) : Bool
      line == "end" || line.starts_with?("end ") || line.starts_with?("end;")
    end

    private def slice_frame(line : String) : RouteFrame?
      return unless call = route_call(line, ["slice"])

      name = parse_first_route_name(call)
      return unless name

      at = parse_options(call)["at"]? || name
      RouteFrame.new(at, name, "")
    end

    private def prefix_frame(line : String, names : Array(String)) : RouteFrame?
      return unless call = route_call(line, names)

      path = ""
      options = parse_options(call)
      if first = parse_first_route_name(call)
        path = first
      end
      path = options["path"]? || path

      RouteFrame.new(path)
    end

    private def route_call(line : String, names : Array(String)) : String?
      names.each do |name|
        next unless line.starts_with?(name)
        next if line.size > name.size && (line[name.size].alphanumeric? || line[name.size] == '_')

        return line[name.size, line.size - name.size].strip
      end

      nil
    end

    private def resource_call(line : String) : NamedTuple(kind: String, name: String, options: Hash(String, String))?
      return unless call = route_call(line, ["resources", "resource"])
      kind = line.starts_with?("resources") ? "resources" : "resource"
      name = parse_first_route_name(call)
      return unless name

      {kind: kind, name: name, options: parse_options(call)}
    end

    private def expand_resource(resource, stack : Array(RouteFrame), details : Details) : Tuple(Array(RouteEndpoint), RouteFrame)
      routes = [] of RouteEndpoint
      resource_name = resource[:name]
      singular = singularize_resource(resource_name)
      action_prefix = join_action_parts(current_action_prefix(stack), resource_name)
      actions = resource_actions(resource[:kind], resource[:options])

      resource_routes(resource[:kind], resource_name, singular).each do |action, method, path_suffix|
        next unless actions.includes?(action)

        endpoint = Endpoint.new(join_paths(current_path_prefix(stack), path_suffix), method, details.dup)
        routes << RouteEndpoint.new(endpoint, join_action_parts(action_prefix, action))
      end

      nested_path = if resource[:kind] == "resources"
                      join_paths(resource_name, ":#{singular}_id")
                    else
                      resource_name
                    end
      nested_frame = RouteFrame.new(nested_path, nil, action_prefix)

      {routes, nested_frame}
    end

    private def resource_routes(kind : String, resource_name : String, singular : String)
      if kind == "resource"
        [
          {"show", "GET", resource_name},
          {"new", "GET", "#{resource_name}/new"},
          {"create", "POST", resource_name},
          {"edit", "GET", "#{resource_name}/edit"},
          {"update", "PATCH", resource_name},
          {"destroy", "DELETE", resource_name},
        ]
      else
        [
          {"index", "GET", resource_name},
          {"new", "GET", "#{resource_name}/new"},
          {"create", "POST", resource_name},
          {"show", "GET", "#{resource_name}/:id"},
          {"edit", "GET", "#{resource_name}/:id/edit"},
          {"update", "PATCH", "#{resource_name}/:id"},
          {"destroy", "DELETE", "#{resource_name}/:id"},
        ]
      end
    end

    private def resource_actions(kind : String, options : Hash(String, String)) : Set(String)
      defaults = if kind == "resource"
                   Set{"show", "new", "create", "edit", "update", "destroy"}
                 else
                   Set{"index", "new", "create", "show", "edit", "update", "destroy"}
                 end

      if only = options["only"]?
        return Set(String).new(parse_action_names(only))
      end

      if except = options["except"]?
        parse_action_names(except).each { |action| defaults.delete(action) }
      end

      defaults
    end

    private def parse_options(args : String) : Hash(String, String)
      options = {} of String => String

      args.scan(/(\w+):\s*("[^"]*"|'[^']*'|%i\[[^\]]+\]|\[[^\]]+\]|:\w+)/) do |match|
        key = match[1]
        value = match[2].strip
        options[key] = unquote_option(value)
      end

      options
    end

    private def parse_first_route_name(args : String) : String?
      if m = args.match(/^\s*(?::([A-Za-z_][\w]*)|['"]([^'"]+)['"])/)
        return (m[1]? || m[2]?).to_s
      end

      nil
    end

    private def parse_action_names(value : String) : Array(String)
      names = [] of String
      value.scan(/:([A-Za-z_][\w]*)|([A-Za-z_][\w]*)/) do |match|
        name = match[1]? || match[2]?
        next unless name
        next if name == "i"

        names << name
      end
      names
    end

    private def unquote_option(value : String) : String
      value = value.strip
      if (value.starts_with?("'") && value.ends_with?("'")) || (value.starts_with?("\"") && value.ends_with?("\""))
        return value[1, value.size - 2]
      end
      return value[1, value.size - 1] if value.starts_with?(":")

      value
    end

    private def current_path_prefix(stack : Array(RouteFrame)) : String
      parts = stack.map(&.path).reject(&.empty?)
      join_paths(parts)
    end

    private def current_slice(stack : Array(RouteFrame)) : String?
      stack.reverse_each do |frame|
        return frame.slice if frame.slice
      end

      nil
    end

    private def current_action_prefix(stack : Array(RouteFrame)) : String
      parts = stack.map(&.action_prefix).reject(&.empty?)
      join_action_parts(parts)
    end

    private def join_paths(parts : Array(String)) : String
      normalized = parts.flat_map(&.split('/')).reject(&.empty?)
      normalized.empty? ? "/" : "/#{normalized.join("/")}"
    end

    private def join_paths(prefix : String, suffix : String) : String
      join_paths([prefix, suffix])
    end

    private def normalize_route_path(path : String) : String
      path.gsub(/\#\{([^}]+)\}/) { |_| "{#{$~[1].strip}}" }
    end

    private def join_action_parts(parts : Array(String)) : String
      parts.flat_map(&.split(/[.\/]/)).reject(&.empty?).join(".")
    end

    private def join_action_parts(prefix : String, suffix : String) : String
      join_action_parts([prefix, suffix])
    end

    private def singularize_resource(name : String) : String
      return name[0, name.size - 3] + "y" if name.ends_with?("ies") && name.size > 3
      return name[0, name.size - 1] if name.ends_with?("s") && name.size > 1

      name
    end

    private def extract_action_target(content : String) : String?
      if match = content.match(/to:\s*['"](.+?)['"]/)
        return match[1]
      end

      nil
    end

    private def find_action_path(target : String, framework_root : String, slice : String?) : String
      action = normalize_action_target(target)
      candidates = [] of String

      if slice
        candidates << "#{framework_root}/slices/#{slice}/actions/#{action}.rb"
        candidates << "#{framework_root}/slices/#{slice}/lib/actions/#{action}.rb"
        candidates << "#{framework_root}/slices/#{slice}/controllers/#{action}.rb"
        candidates << "#{framework_root}/apps/#{slice}/controllers/#{action}.rb"
      end

      candidates << "#{framework_root}/app/actions/#{action}.rb"
      candidates << "#{framework_root}/app/controllers/#{action}.rb"
      candidates << "#{framework_root}/actions/#{action}.rb"
      candidates << "#{framework_root}/controllers/#{action}.rb"
      candidates << "#{framework_root}/lib/actions/#{action}.rb"

      candidates.find { |path| File.exists?(path) } || ""
    end

    private def normalize_action_target(target : String) : String
      target.gsub("::", "/").gsub("#", "/").gsub(".", "/")
    end

    private def scan_action_params(endpoint : Endpoint, lines : Array(String))
      params_depth = 0

      lines.each do |line|
        stripped = line.strip
        # dry-validation params blocks nest (`required(:address).hash do ...
        # end`), so track depth and exit only on the OUTERMOST `end`. A plain
        # boolean exited on the first inner `end`, dropping later params and
        # fabricating query params from DSL lines still inside the block.
        if params_depth == 0 && stripped == "params do"
          params_depth = 1
          next
        end

        if params_depth > 0
          if closes_ruby_block?(stripped)
            params_depth -= 1
            next if params_depth == 0
          else
            params_depth += ruby_do_block_open_delta(stripped)
          end
        end

        in_params_block = params_depth > 0

        # Extract params from params block
        # Matches required(:name) or optional(:name) - validation methods like
        # .filled(), .value(), .maybe() are chained after and don't affect extraction
        if in_params_block
          # Match required(:name) or optional(:name) with any validation method
          line.scan(/(?:required|optional)\(:([\w]+)\)/) do |match|
            if match.size > 1
              param_name = match[1]
              # Determine if it's JSON or form based on content type
              param_type = "json"
              endpoint.push_param(Param.new(param_name, "", param_type))
            end
          end
        end

        # Extract query parameters from request.params[:name]
        line.scan(/request\.params\[:([\w]+)\]/) do |match|
          if match.size > 1
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "query"))
          end
        end

        # Extract query parameters from request.params["name"]
        line.scan(/request\.params\[['"](\w+)['"]\]/) do |match|
          if match.size > 1
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "query"))
          end
        end

        # Extract query parameters from params[:name] (without request prefix)
        # Use word boundary to avoid matching params inside method names or identifiers
        # Avoid matching inside params do blocks
        unless in_params_block
          line.scan(/(?<!\.)\bparams\[:([\w]+)\]/) do |match|
            if match.size > 1
              param_name = match[1]
              endpoint.push_param(Param.new(param_name, "", "query"))
            end
          end
        end

        # Extract query parameters from params["name"] (without request prefix)
        # Use word boundary to avoid matching params inside method names or identifiers
        # Avoid matching inside params do blocks
        unless in_params_block
          line.scan(/(?<!\.)\bparams\[['"](\w+)['"]\]/) do |match|
            if match.size > 1
              param_name = match[1]
              endpoint.push_param(Param.new(param_name, "", "query"))
            end
          end
        end

        # Extract header parameters from request.headers['name'] or request.headers["name"]
        line.scan(/request\.headers\[['"](.+?)['"]\]/) do |match|
          if match.size > 1
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "header"))
          end
        end

        # Extract cookie parameters from request.cookies['name'] or request.cookies["name"]
        line.scan(/request\.cookies\[['"](.+?)['"]\]/) do |match|
          if match.size > 1
            param_name = match[1]
            endpoint.push_param(Param.new(param_name, "", "cookie"))
          end
        end

        # Extract environment headers from request.env['HTTP_*']
        line.scan(/request\.env\[['"]HTTP_(.+?)['"]\]/) do |match|
          if match.size > 1
            # Convert HTTP_USER_AGENT to User-Agent format
            header_name = match[1].split('_').map(&.capitalize).join('-')
            endpoint.push_param(Param.new(header_name, "", "header"))
          end
        end
      end
    end

    private def attach_handle_callees(endpoint : Endpoint, action_path : String, lines : Array(String))
      if block = extract_action_body(lines, ["handle", "call"])
        body, body_start_line = block
        callees = Noir::RubyCalleeExtractor.callees_for_body(body, action_path, body_start_line)
        attach_ruby_callees(endpoint, callees)
      end

      extract_plug_bodies(lines).each do |plug_body, plug_body_start_line|
        callees = Noir::RubyCalleeExtractor.callees_for_body(plug_body, action_path, plug_body_start_line)
        attach_ruby_callees(endpoint, callees)
      end
    end

    private def extract_action_body(lines : Array(String), names : Array(String)) : Tuple(String, Int32)?
      index = 0
      # Hoisted out of the loop: an interpolated regex literal recompiles
      # (PCRE2 JIT) on every evaluation, i.e. once per line.
      name_pattern = names.join("|")
      def_regex = /^(?:private\s+|protected\s+|public\s+)?def\s+(?:self\.)?(?:#{name_pattern})\b/

      while index < lines.size
        stripped = Noir::RubyCalleeExtractor.strip_comment(lines[index]).strip
        if match = stripped.match(def_regex)
          inline_body, closed_on_def_line = inline_def_body(stripped, match[0])
          body_lines = [] of String
          body_start_line = inline_body ? index + 1 : index + 2
          body_lines << inline_body if inline_body

          unless closed_on_def_line
            depth = 1
            index += 1

            while index < lines.size
              raw_body_line = lines[index]
              body_line = Noir::RubyCalleeExtractor.strip_comment(raw_body_line).strip

              if closes_ruby_block?(body_line)
                depth -= 1
                break if depth == 0
                body_lines << raw_body_line
                index += 1
                next
              end

              body_lines << raw_body_line
              depth += ruby_do_block_open_delta(body_line)
              index += 1
            end
          end

          return {body_lines.join("\n"), body_start_line}
        end

        index += 1
      end
    end

    private def extract_plug_bodies(lines : Array(String)) : Array(Tuple(String, Int32))
      plug_names = [] of String
      lines.each do |line|
        stripped = Noir::RubyCalleeExtractor.strip_comment(line).strip
        if match = stripped.match(/^plug\s+:([A-Za-z_]\w*[!?=]?)/)
          plug_names << match[1]
        end
      end

      plug_names.compact_map { |name| extract_action_body(lines, [name]) }
    end

    private def inline_def_body(line : String, match_text : String) : Tuple(String?, Bool)
      return {nil, false} if match_text.size >= line.size

      tail = line[match_text.size, line.size - match_text.size].strip
      tail = tail.sub(/^\([^)]*\)\s*/, "")
      if tail.starts_with?("=")
        body = tail[1, tail.size - 1].strip
        return {body.empty? ? nil : body, true}
      end

      return {nil, false} unless tail.starts_with?(";")

      tail = tail[1, tail.size - 1].strip
      if match = tail.match(/^(.*?)(?:;\s*)?end\b/)
        body = match[1].strip
        return {body.empty? ? nil : body, true}
      end

      {tail.empty? ? nil : tail, false}
    end

    private def closes_ruby_block?(line : String) : Bool
      !!line.match(/^end\b/)
    end
  end
end
