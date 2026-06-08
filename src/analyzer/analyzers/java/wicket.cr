require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/java_route_extractor_ts"
require "../../../miniparsers/java_callee_extractor"

module Analyzer::Java
  class Wicket < Analyzer
    JAVA_EXTENSION = "java"
    WICKET_MARKERS = [
      "org.apache.wicket",
      "WebApplication",
      "mountPage",
      "mountPackage",
      "mountResource",
      "MountPath",
      "MountedMapper",
      "PackageMapper",
      "ResourceMapper",
      "org.wicketstuff.rest",
      "MethodMapping",
      "ResourcePath",
      "LambdaRestMounter",
    ]

    MAPPER_CLASSES = Set{
      "MountedMapper",
      "PackageMapper",
      "ResourceMapper",
      "IndexedParamUrlCodingStrategy",
      "MixedParamUrlCodingStrategy",
      "MixedParamHybridUrlCodingStrategy",
      "HybridUrlCodingStrategy",
      "QueryStringUrlCodingStrategy",
    }

    PACKAGE_MAPPER_CLASSES  = Set{"PackageMapper"}
    RESOURCE_MAPPER_CLASSES = Set{"ResourceMapper"}
    REST_LAMBDA_METHODS     = Set{"get", "post", "put", "delete", "patch", "head", "options", "trace"}

    alias FileInfo = NamedTuple(path: String, content: String, constants: Hash(String, String), base: String)
    alias RestRoute = NamedTuple(path: String, method: String, file_path: String, line: Int32, callees: Array(Callee), params: Array(Param))
    alias RestMount = NamedTuple(path: String, file_path: String, line: Int32)
    alias ScopedClassKey = Tuple(String, String)
    alias PageMountIndex = Hash(ScopedClassKey, Array(String))
    alias RestRouteIndex = Hash(ScopedClassKey, Array(RestRoute))
    alias RestMountIndex = Hash(ScopedClassKey, RestMount)

    @include_callee : Bool = false

    def analyze
      @include_callee = callees_needed?
      files = java_files_with_content
      page_mounts = PageMountIndex.new { |hash, key| hash[key] = [] of String }
      rest_routes = RestRouteIndex.new { |hash, key| hash[key] = [] of RestRoute }
      rest_mounts = RestMountIndex.new
      seen = Set(String).new

      files.each do |file|
        collect_rest_resource_annotations(file, rest_routes, rest_mounts)
      end

      emit_resource_path_routes(rest_routes, rest_mounts, seen)

      files.each do |file|
        collect_mount_path_annotations(file, page_mounts, seen)
        collect_mount_calls(file, page_mounts, rest_routes, seen)
        collect_mapper_mounts(file, page_mounts, seen)
        collect_local_page_mount_helpers(file, page_mounts, seen)
        collect_rest_lambda_mounts(file, seen)
      end

      files.each do |file|
        collect_navigation_mounts(file, page_mounts, seen)
      end

      Fiber.yield
      @result
    end

    private def java_files_with_content : Array(FileInfo)
      files = [] of FileInfo

      all_files.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless WICKET_MARKERS.any? { |marker| content.includes?(marker) }

        files << {
          path:      path,
          content:   content,
          constants: string_constants_for(content),
          base:      configured_base_for(path),
        }
      end

      files
    end

    private def scoped_class_key(file : FileInfo, class_name : String) : ScopedClassKey
      {file[:base], class_name}
    end

    private def scoped_class_key(base : String, class_name : String) : ScopedClassKey
      {base, class_name}
    end

    private def collect_mount_path_annotations(file : FileInfo,
                                               page_mounts : PageMountIndex,
                                               seen : Set(String))
      content = file[:content]
      content.scan(/@(?:[A-Za-z_][A-Za-z0-9_]*\.)*MountPath\b/) do |match|
        marker = match.begin(0) || 0
        after = match.end(0) || marker
        args = ""
        scan_from = after

        scan_from = skip_whitespace(content, scan_from)
        if scan_from < content.size && content[scan_from] == '('
          if close_idx = find_matching_paren(content, scan_from)
            args = content[(scan_from + 1)...close_idx]
            scan_from = close_idx + 1
          end
        end

        class_name = next_class_name(content, scan_from)
        next if class_name.empty?

        mount_path_values(args, class_name, file[:constants]).each do |mount_path|
          normalized = normalize_mount_path(mount_path)
          key = scoped_class_key(file, class_name)
          page_mounts[key] << normalized unless page_mounts[key].includes?(normalized)
          add_endpoint(normalized, file[:path], line_for_offset(content, marker), seen)
        end
      end
    end

    private def collect_mount_calls(file : FileInfo,
                                    page_mounts : PageMountIndex,
                                    rest_routes : RestRouteIndex,
                                    seen : Set(String))
      {"mountPage", "mountPackage", "mountResource"}.each do |method_name|
        scan_method_calls(file[:content], method_name) do |args, offset|
          arguments = split_arguments(args)
          next if arguments.empty?

          mount_path = resolve_string_expression(arguments[0], file[:constants])
          next unless mount_path

          normalized = normalize_mount_path(mount_path)

          if method_name == "mountResource"
            if resource_key = rest_resource_class_key(args, file[:base], rest_routes)
              if routes = rest_routes[resource_key]?
                routes.each do |route|
                  add_endpoint(join_mount_paths(normalized, route[:path]), route[:file_path], route[:line], seen, route[:method], route[:callees], route[:params])
                end
                next
              end
            end
          end

          endpoint_path = method_name == "mountPackage" ? package_mount_path(normalized) : normalized
          add_endpoint(endpoint_path, file[:path], line_for_offset(file[:content], offset), seen)

          if method_name == "mountPage"
            if page_class = class_literal_name(arguments[1]?)
              key = scoped_class_key(file, page_class)
              page_mounts[key] << normalized unless page_mounts[key].includes?(normalized)
            end
          end
        end
      end
    end

    private def collect_mapper_mounts(file : FileInfo,
                                      page_mounts : PageMountIndex,
                                      seen : Set(String))
      file[:content].scan(/\bnew\s+(?:[A-Za-z_][A-Za-z0-9_]*\.)*([A-Za-z_][A-Za-z0-9_]*)\s*\(/) do |match|
        mapper_class = match[1]
        next unless MAPPER_CLASSES.includes?(mapper_class)

        open_idx = (match.end(0) || 1) - 1
        close_idx = find_matching_paren(file[:content], open_idx)
        next unless close_idx

        args = file[:content][(open_idx + 1)...close_idx]
        arguments = split_arguments(args)
        next if arguments.empty?

        mount_path = resolve_string_expression(arguments[0], file[:constants])
        next unless mount_path

        normalized = normalize_mount_path(mount_path)
        endpoint_path = PACKAGE_MAPPER_CLASSES.includes?(mapper_class) ? package_mount_path(normalized) : normalized
        add_endpoint(endpoint_path, file[:path], line_for_offset(file[:content], match.begin(0) || open_idx), seen)

        next if RESOURCE_MAPPER_CLASSES.includes?(mapper_class) || PACKAGE_MAPPER_CLASSES.includes?(mapper_class)
        if page_class = class_literal_name(arguments[1]?)
          key = scoped_class_key(file, page_class)
          page_mounts[key] << normalized unless page_mounts[key].includes?(normalized)
        end
      end
    end

    private def collect_local_page_mount_helpers(file : FileInfo,
                                                 page_mounts : PageMountIndex,
                                                 seen : Set(String))
      helper_methods = local_page_mount_helpers(file[:content])
      return if helper_methods.empty?

      helper_methods.each do |method_name, indexes|
        scan_method_calls(file[:content], method_name) do |args, offset|
          arguments = split_arguments(args)
          next unless arguments.size > indexes[0] && arguments.size > indexes[1]

          mount_path = resolve_string_expression(arguments[indexes[0]], file[:constants])
          next unless mount_path

          normalized = normalize_mount_path(mount_path)
          add_endpoint(normalized, file[:path], line_for_offset(file[:content], offset), seen)

          if page_class = class_literal_name(arguments[indexes[1]]?)
            key = scoped_class_key(file, page_class)
            page_mounts[key] << normalized unless page_mounts[key].includes?(normalized)
          end
        end
      end
    end

    private def collect_rest_resource_annotations(file : FileInfo,
                                                  rest_routes : RestRouteIndex,
                                                  rest_mounts : RestMountIndex)
      collect_resource_path_annotations(file, rest_mounts)

      class_name = first_class_name(file[:content])
      return if class_name.empty?

      # First pass collects the route shape, the enclosing handler method
      # name, and the handler's request parameters (from wicketstuff-rest
      # @RequestParam/@HeaderParam/@CookieParam/@RequestBody annotations);
      # callees are filled in a single tree-sitter parse below (only when
      # callee/ai-context enrichment is requested).
      pending = [] of NamedTuple(path: String, method: String, line: Int32, method_name: String, params: Array(Param))
      file[:content].scan(/@(?:[A-Za-z_][A-Za-z0-9_]*\.)*MethodMapping\b/) do |match|
        marker = match.begin(0) || 0
        after = match.end(0) || marker
        args = ""
        scan_from = skip_whitespace(file[:content], after)

        if scan_from < file[:content].size && file[:content][scan_from] == '('
          if close_idx = find_matching_paren(file[:content], scan_from)
            args = file[:content][(scan_from + 1)...close_idx]
            scan_from = close_idx + 1
          end
        end

        path, method = method_mapping_values(args, file[:constants])
        method_name, param_list = rest_handler_signature(file[:content], scan_from)
        pending << {
          path:        normalize_mount_path(path),
          method:      method,
          line:        line_for_offset(file[:content], marker),
          method_name: method_name,
          params:      rest_method_params(param_list),
        }
      end
      return if pending.empty?

      callee_map = method_callees_for(file, class_name, pending.map(&.[:method_name]))
      key = scoped_class_key(file, class_name)
      pending.each do |entry|
        rest_routes[key] << {
          path:      entry[:path],
          method:    entry[:method],
          file_path: file[:path],
          line:      entry[:line],
          callees:   callee_map[entry[:method_name]]? || [] of Callee,
          params:    entry[:params],
        }
      end
    end

    # Parse the file once and return a method-name → 1-hop-callees map for
    # the requested handler methods. Empty unless callee/ai-context
    # enrichment was requested. Mirrors the Struts2/Spring callee scope:
    # call sites inside the same-file handler body, no cross-file
    # resolution.
    private def method_callees_for(file : FileInfo,
                                   class_name : String,
                                   method_names : Array(String)) : Hash(String, Array(Callee))
      result = Hash(String, Array(Callee)).new
      return result unless @include_callee

      Noir::TreeSitter.parse_java(file[:content]) do |root|
        method_names.uniq.each do |method_name|
          next if method_name.empty? || result.has_key?(method_name)

          callees = [] of Callee
          Noir::JavaCalleeExtractor.callees_in_method(root, file[:content], file[:path], class_name, method_name).each do |entry|
            name, callee_path, callee_line = entry
            callees << Callee.new(name, path: callee_path, line: callee_line)
          end
          result[method_name] = callees
        end
      end

      result
    rescue e : Exception
      @logger.debug "Failed to extract Wicket callees in #{file[:path]}: #{e.message}"
      Hash(String, Array(Callee)).new
    end

    # Name + raw parameter-list text of the method declared immediately
    # after a `@MethodMapping` annotation. wicketstuff-rest handler
    # methods are public, so we anchor on the access modifier and capture
    # the identifier that precedes the parameter list, then the balanced
    # `(...)` that follows.
    private def rest_handler_signature(content : String, offset : Int32) : Tuple(String, String)
      rest = content[offset..]? || ""
      match = rest.match(/\b(?:public|protected|private)\b[^;{}=]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*\(/)
      return {"", ""} unless match

      name = match[1]
      open_abs = offset + (match.end(0) || 1) - 1
      close_abs = find_matching_paren(content, open_abs)
      return {name, ""} unless close_abs

      {name, content[(open_abs + 1)...close_abs]}
    end

    # Map wicketstuff-rest handler parameters to request parameters.
    # Path parameters are sourced from the `{...}` placeholders in the
    # mount URL, so an unannotated method parameter (bound positionally to
    # a path placeholder) is intentionally skipped here to avoid
    # duplicates. `@PathParam` is likewise covered by the URL placeholder.
    private def rest_method_params(param_list : String) : Array(Param)
      params = [] of Param
      return params if param_list.strip.empty?

      split_arguments(param_list).each do |raw|
        decl = raw.strip
        next if decl.empty?

        java_name = decl.match(/([A-Za-z_][A-Za-z0-9_]*)\s*$/).try(&.[1]) || ""

        if match = decl.match(/@(?:[A-Za-z_][A-Za-z0-9_]*\.)*RequestParam\b\s*\(([^)]*)\)/)
          name = annotation_first_string(match[1]) || java_name
          add_rest_param(params, name, "query")
        elsif match = decl.match(/@(?:[A-Za-z_][A-Za-z0-9_]*\.)*HeaderParam\b\s*\(([^)]*)\)/)
          name = annotation_first_string(match[1]) || java_name
          add_rest_param(params, name, "header")
        elsif match = decl.match(/@(?:[A-Za-z_][A-Za-z0-9_]*\.)*CookieParam\b\s*\(([^)]*)\)/)
          name = annotation_first_string(match[1]) || java_name
          add_rest_param(params, name, "cookie")
        elsif decl.matches?(/@(?:[A-Za-z_][A-Za-z0-9_]*\.)*RequestBody\b/)
          add_rest_param(params, java_name, "json")
        end
      end
      params
    end

    private def add_rest_param(params : Array(Param), name : String, type : String)
      return if name.empty?
      return if params.any? { |param| param.name == name && param.param_type == type }
      params << Param.new(name, "", type)
    end

    # First string literal in an annotation argument list, handling both
    # the shorthand `@X("name")` and the explicit `@X(value = "name", …)`
    # forms.
    private def annotation_first_string(args : String) : String?
      stripped = args.strip
      if value_match = stripped.match(/\bvalue\s*=\s*"((?:\\.|[^"\\])*)"/)
        return value_match[1]
      end
      if literal = stripped.match(/"((?:\\.|[^"\\])*)"/)
        return literal[1]
      end
      nil
    end

    private def collect_resource_path_annotations(file : FileInfo,
                                                  rest_mounts : RestMountIndex)
      file[:content].scan(/@(?:[A-Za-z_][A-Za-z0-9_]*\.)*ResourcePath\b/) do |match|
        marker = match.begin(0) || 0
        after = match.end(0) || marker
        args = ""
        scan_from = skip_whitespace(file[:content], after)

        if scan_from < file[:content].size && file[:content][scan_from] == '('
          if close_idx = find_matching_paren(file[:content], scan_from)
            args = file[:content][(scan_from + 1)...close_idx]
            scan_from = close_idx + 1
          end
        end

        class_name = next_class_name(file[:content], scan_from)
        next if class_name.empty?

        if mount_path = first_annotation_path_value(args, file[:constants])
          rest_mounts[scoped_class_key(file, class_name)] = {
            path:      normalize_mount_path(mount_path),
            file_path: file[:path],
            line:      line_for_offset(file[:content], marker),
          }
        end
      end
    end

    private def emit_resource_path_routes(rest_routes : RestRouteIndex,
                                          rest_mounts : RestMountIndex,
                                          seen : Set(String))
      rest_mounts.each do |class_key, mount|
        routes = rest_routes[class_key]?
        if routes && !routes.empty?
          routes.each do |route|
            add_endpoint(join_mount_paths(mount[:path], route[:path]), route[:file_path], route[:line], seen, route[:method], route[:callees], route[:params])
          end
        else
          add_endpoint(mount[:path], mount[:file_path], mount[:line], seen)
        end
      end
    end

    private def collect_rest_lambda_mounts(file : FileInfo, seen : Set(String))
      scan_method_calls(file[:content], "mountRestResource") do |args, offset|
        arguments = split_arguments(args)
        next if arguments.size < 2

        method = http_method_name(arguments[0])
        path = resolve_string_expression(arguments[1], file[:constants])
        next unless method && path

        add_endpoint(normalize_mount_path(path), file[:path], line_for_offset(file[:content], offset), seen, method)
      end

      lambda_mounters = lambda_rest_mounter_variables(file[:content])
      return if lambda_mounters.empty?

      REST_LAMBDA_METHODS.each do |method_name|
        lambda_mounters.each do |receiver|
          scan_receiver_method_calls(file[:content], receiver, method_name) do |args, offset|
            arguments = split_arguments(args)
            next if arguments.empty?

            if path = resolve_string_expression(arguments[0], file[:constants])
              add_endpoint(normalize_mount_path(path), file[:path], line_for_offset(file[:content], offset), seen, method_name.upcase)
            end
          end
        end
      end
    end

    private def collect_navigation_mounts(file : FileInfo,
                                          page_mounts : PageMountIndex,
                                          seen : Set(String))
      file[:content].scan(/\b(?:new\s+)?BookmarkablePageLink(?:\s*<[^;()]*>)?\s*\(/) do |match|
        open_idx = (match.end(0) || 1) - 1
        emit_known_page_class_links(file, page_mounts, seen, open_idx, match.begin(0) || open_idx)
      end

      scan_method_calls(file[:content], "setResponsePage") do |args, offset|
        page_classes = class_literal_names(args)
        args.scan(/\bnew\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(/) do |new_match|
          page_classes << new_match[1]
        end
        emit_page_class_endpoints(file, page_mounts, seen, page_classes, offset)
      end
    end

    private def emit_known_page_class_links(file : FileInfo,
                                            page_mounts : PageMountIndex,
                                            seen : Set(String),
                                            open_idx : Int32,
                                            offset : Int32)
      close_idx = find_matching_paren(file[:content], open_idx)
      return unless close_idx

      args = file[:content][(open_idx + 1)...close_idx]
      emit_page_class_endpoints(file, page_mounts, seen, class_literal_names(args), offset)
    end

    private def emit_page_class_endpoints(file : FileInfo,
                                          page_mounts : PageMountIndex,
                                          seen : Set(String),
                                          page_classes : Array(String),
                                          offset : Int32)
      page_classes.uniq.each do |page_class|
        page_mounts[scoped_class_key(file, page_class)]?.try &.each do |mount_path|
          add_endpoint(mount_path, file[:path], line_for_offset(file[:content], offset), seen)
        end
      end
    end

    private def add_endpoint(path : String, file_path : String, line : Int32, seen : Set(String))
      add_endpoint(path, file_path, line, seen, "GET")
    end

    private def add_endpoint(path : String, file_path : String, line : Int32, seen : Set(String), method : String, callees : Array(Callee) = [] of Callee, extra_params : Array(Param) = [] of Param)
      params = path_params(path)
      extra_params.each do |param|
        next if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
        params << param
      end

      endpoint = Endpoint.new(path, method, params, Details.new(PathInfo.new(file_path, line)))
      key = endpoint_key(endpoint)
      return if seen.includes?(key)

      seen << key
      callees.each { |callee| endpoint.push_callee(callee) }
      @result << endpoint
    end

    private def endpoint_key(endpoint : Endpoint) : String
      params = endpoint.params.map { |param| "#{param.param_type}:#{param.name}" }.sort!.join(",")
      "#{endpoint.method}::#{endpoint.url}::#{params}"
    end

    private def path_params(path : String) : Array(Param)
      params = [] of Param
      path.scan(/\{([A-Za-z_][A-Za-z0-9_]*)\}/) do |match|
        name = match[1]
        params << Param.new(name, "", "path") unless params.any? { |param| param.name == name && param.param_type == "path" }
      end
      params
    end

    private def mount_path_values(args : String,
                                  class_name : String,
                                  constants : Hash(String, String)) : Array(String)
      return ["/#{class_name}"] if args.strip.empty?

      values = [] of String
      split_arguments(args).each do |argument|
        name, expression = split_named_argument(argument)
        case name
        when "", "value", "path"
          if value = resolve_string_expression(expression, constants)
            values << value
          end
        when "alt", "aliases"
          values.concat(resolve_string_array(expression, constants))
        end
      end

      values = ["/#{class_name}"] if values.empty?
      values.uniq
    end

    private def method_mapping_values(args : String, constants : Hash(String, String)) : Tuple(String, String)
      path = "/"
      method = "GET"

      split_arguments(args).each do |argument|
        name, expression = split_named_argument(argument)
        case name
        when "", "value", "path"
          if value = resolve_string_expression(expression, constants)
            path = value
          end
        when "httpMethod", "method"
          method = http_method_name(expression) || method
        end
      end

      {path, method}
    end

    private def first_annotation_path_value(args : String, constants : Hash(String, String)) : String?
      split_arguments(args).each do |argument|
        name, expression = split_named_argument(argument)
        next unless name.empty? || name == "value" || name == "path"

        if value = resolve_string_expression(expression, constants)
          return value
        end
      end
    end

    private def split_named_argument(argument : String) : Tuple(String, String)
      depth = 0
      in_string = false
      escape = false

      argument.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when '='
          return {argument[...index].strip, argument[(index + 1)..].strip} if depth.zero?
        end
      end

      {"", argument.strip}
    end

    private def resolve_string_array(expression : String, constants : Hash(String, String)) : Array(String)
      trimmed = expression.strip
      if trimmed.starts_with?("{") && trimmed.ends_with?("}")
        return split_arguments(trimmed[1...-1]).compact_map { |part| resolve_string_expression(part, constants) }
      end

      if value = resolve_string_expression(trimmed, constants)
        return [value]
      end

      [] of String
    end

    private def scan_method_calls(content : String, method_name : String, &block : String, Int32 ->)
      offset = 0
      while marker = content.index(method_name, offset)
        offset = marker + method_name.size
        next unless call_name_at?(content, marker, method_name)

        open_idx = skip_whitespace(content, marker + method_name.size)
        next unless open_idx < content.size && content[open_idx] == '('

        close_idx = find_matching_paren(content, open_idx)
        next unless close_idx

        block.call(content[(open_idx + 1)...close_idx], marker)
      end
    end

    private def call_name_at?(content : String, marker : Int32, method_name : String) : Bool
      before = marker.zero? ? '\0' : content[marker - 1]
      return false if before.ascii_alphanumeric? || before == '_' || before == '$'

      after = marker + method_name.size
      after = skip_whitespace(content, after)
      after < content.size && content[after] == '('
    end

    private def scan_receiver_method_calls(content : String, receiver : String, method_name : String, &block : String, Int32 ->)
      offset = 0
      pattern = "#{receiver}.#{method_name}"
      while marker = content.index(pattern, offset)
        offset = marker + pattern.size
        next unless receiver_method_call_at?(content, marker, receiver, method_name)

        open_idx = skip_whitespace(content, marker + pattern.size)
        next unless open_idx < content.size && content[open_idx] == '('

        close_idx = find_matching_paren(content, open_idx)
        next unless close_idx

        block.call(content[(open_idx + 1)...close_idx], marker)
      end
    end

    private def receiver_method_call_at?(content : String, marker : Int32, receiver : String, method_name : String) : Bool
      before = marker.zero? ? '\0' : content[marker - 1]
      return false if before.ascii_alphanumeric? || before == '_' || before == '$'

      dot_idx = marker + receiver.size
      return false unless dot_idx < content.size && content[dot_idx] == '.'

      after = dot_idx + 1 + method_name.size
      after = skip_whitespace(content, after)
      after < content.size && content[after] == '('
    end

    private def split_arguments(args : String) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      in_string = false
      escape = false

      args.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{', '<'
          depth += 1
        when ')', ']', '}', '>'
          depth -= 1 if depth > 0
        when ','
          if depth.zero?
            parts << args[start...index].strip
            start = index + 1
          end
        end
      end

      tail = args[start..]?.try(&.strip)
      parts << tail if tail && !tail.empty?
      parts
    end

    private def class_literal_name(argument : String?) : String?
      return unless argument

      if match = argument.match(/\b([A-Za-z_][A-Za-z0-9_.]*)\s*\.class\b/)
        match[1].split('.').last
      end
    end

    private def class_literal_names(source : String) : Array(String)
      names = [] of String
      source.scan(/\b([A-Za-z_][A-Za-z0-9_.]*)\s*\.class\b/) do |match|
        names << match[1].split('.').last
      end
      names
    end

    private def normalize_mount_path(path : String) : String
      normalized = path.strip
      normalized = normalized.gsub(/\$\{([A-Za-z_][A-Za-z0-9_]*)\}/, "{\\1}")
      normalized = normalized.gsub(/#\{([A-Za-z_][A-Za-z0-9_]*)\}/, "{\\1}")
      normalized = normalized.gsub(/\{([A-Za-z_][A-Za-z0-9_]*):[^}]+\}/, "{\\1}")
      normalized = normalized.gsub(%r{/+}, "/")
      return "/" if normalized.empty?
      normalized.starts_with?("/") ? normalized : "/#{normalized}"
    end

    private def join_mount_paths(base_path : String, child_path : String) : String
      base = normalize_mount_path(base_path)
      child = normalize_mount_path(child_path)
      return base if child == "/"
      return child if base == "/"
      normalize_mount_path("#{base.rstrip('/')}/#{child.lstrip('/')}")
    end

    private def package_mount_path(path : String) : String
      path == "/" ? "/**" : "#{path.rstrip('/')}/**"
    end

    private def first_class_name(content : String) : String
      next_class_name(content, 0)
    end

    private def next_class_name(content : String, offset : Int32) : String
      rest = content[offset..]? || ""
      if match = rest.match(/\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\b/)
        return match[1]
      end

      ""
    end

    private def rest_resource_class_key(source : String, base : String, rest_routes : RestRouteIndex) : ScopedClassKey?
      source.scan(/\bnew\s+([A-Za-z_][A-Za-z0-9_.]*)\s*(?:<[^;()]*>)?\s*\(/) do |match|
        class_name = match[1].split('.').last
        key = scoped_class_key(base, class_name)
        return key if rest_routes.has_key?(key)
      end

      source.scan(/\b([A-Za-z_][A-Za-z0-9_.]*)\s*\.class\b/) do |match|
        class_name = match[1].split('.').last
        key = scoped_class_key(base, class_name)
        return key if rest_routes.has_key?(key)
      end

      nil
    end

    private def http_method_name(expression : String) : String?
      if match = expression.match(/\b(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|TRACE)\b/i)
        match[1].upcase
      end
    end

    private def lambda_rest_mounter_variables(content : String) : Set(String)
      variables = Set(String).new
      content.scan(/\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*new\s+(?:[A-Za-z_][A-Za-z0-9_]*\.)*LambdaRestMounter\s*\(/) do |match|
        variables << match[1]
      end
      variables
    end

    private def local_page_mount_helpers(content : String) : Hash(String, Tuple(Int32, Int32))
      helpers = Hash(String, Tuple(Int32, Int32)).new

      content.scan(/\b(?:public|protected|private)\s+(?:static\s+)?[A-Za-z0-9_<>\[\]\s?,.&]+\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*\{/) do |match|
        method_name = match[1]
        open_idx = (match.end(0) || 1) - 1
        close_idx = find_matching_brace(content, open_idx)
        next unless close_idx

        param_names = method_parameter_names(match[2])
        next if param_names.empty?

        body = content[(open_idx + 1)...close_idx]
        if indexes = mounted_mapper_param_indexes(body, param_names)
          helpers[method_name] = indexes
          next
        end

        if indexes = mount_page_param_indexes(body, param_names)
          helpers[method_name] = indexes
        end
      end

      helpers
    end

    private def method_parameter_names(parameters : String) : Array(String)
      split_arguments(parameters).compact_map do |parameter|
        normalized = parameter.strip.gsub(/\s+/, " ")
        if match = normalized.match(/\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[\])?\s*$/)
          match[1]
        end
      end
    end

    private def mounted_mapper_param_indexes(body : String, param_names : Array(String)) : Tuple(Int32, Int32)?
      body.scan(/\bnew\s+(?:[A-Za-z_][A-Za-z0-9_]*\.)*MountedMapper\s*\(/) do |match|
        open_idx = (match.end(0) || 1) - 1
        close_idx = find_matching_paren(body, open_idx)
        next unless close_idx

        arguments = split_arguments(body[(open_idx + 1)...close_idx])
        next if arguments.size < 2

        path_index = param_names.index(arguments[0].strip)
        class_index = param_names.index(arguments[1].strip)
        return {path_index, class_index} if path_index && class_index
      end
      nil
    end

    private def mount_page_param_indexes(body : String, param_names : Array(String)) : Tuple(Int32, Int32)?
      body.scan(/\bmountPage\s*\(/) do |match|
        open_idx = (match.end(0) || 1) - 1
        close_idx = find_matching_paren(body, open_idx)
        next unless close_idx

        arguments = split_arguments(body[(open_idx + 1)...close_idx])
        next if arguments.size < 2

        path_index = param_names.index(arguments[0].strip)
        class_index = param_names.index(arguments[1].strip)
        return {path_index, class_index} if path_index && class_index
      end
      nil
    end

    private def resolve_string_expression(expression : String,
                                          constants : Hash(String, String)) : String?
      parts = split_string_concat_parts(expression)
      return if parts.empty?

      values = parts.compact_map do |part|
        resolve_string_part(part, constants)
      end

      values.size == parts.size ? values.join : nil
    end

    private def split_string_concat_parts(expression : String) : Array(String)
      parts = [] of String
      start = 0
      depth = 0
      in_string = false
      escape = false

      expression.each_char_with_index do |char, index|
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          next
        end

        case char
        when '"'
          in_string = true
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when '+'
          if depth.zero?
            part = expression[start...index].strip
            parts << part unless part.empty?
            start = index + 1
          end
        end
      end

      tail = expression[start..]?.try(&.strip)
      parts << tail if tail && !tail.empty?
      parts
    end

    private def resolve_string_part(part : String, constants : Hash(String, String)) : String?
      stripped = part.strip
      if stripped.size >= 2 && stripped.starts_with?('"') && stripped.ends_with?('"')
        return unescape_java_string(stripped[1...-1])
      end

      if resolved = constants[stripped]?
        return resolved
      end

      suffix = ".#{stripped}"
      matches = constants.compact_map do |key, value|
        key.ends_with?(suffix) ? value : nil
      end.uniq!
      matches.size == 1 ? matches.first : nil
    end

    private def unescape_java_string(value : String) : String
      value.gsub("\\\"", "\"").gsub("\\\\", "\\")
    end

    private def string_constants_for(content : String) : Hash(String, String)
      constants = Hash(String, String).new
      begin
        Noir::TreeSitter.parse_java(content) do |root|
          constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
        end
      rescue
      end
      constants
    end

    private def skip_whitespace(content : String, offset : Int32) : Int32
      index = offset
      while index < content.size && content[index].ascii_whitespace?
        index += 1
      end
      index
    end

    private def find_matching_paren(code : String, open_idx : Int32) : Int32?
      depth = 1
      index = open_idx + 1
      in_string = false
      escape = false

      while index < code.size
        char = code[index]
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          index += 1
          next
        end

        case char
        when '"'
          in_string = true
        when '('
          depth += 1
        when ')'
          depth -= 1
          return index if depth.zero?
        end
        index += 1
      end
      nil
    end

    private def find_matching_brace(code : String, open_idx : Int32) : Int32?
      depth = 1
      index = open_idx + 1
      in_string = false
      escape = false

      while index < code.size
        char = code[index]
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
          index += 1
          next
        end

        case char
        when '"'
          in_string = true
        when '{'
          depth += 1
        when '}'
          depth -= 1
          return index if depth.zero?
        end
        index += 1
      end
      nil
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      content[0...offset].count('\n') + 1
    end
  end
end
