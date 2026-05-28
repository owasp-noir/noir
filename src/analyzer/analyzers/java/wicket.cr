require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/java_route_extractor_ts"

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

    alias FileInfo = NamedTuple(path: String, content: String, constants: Hash(String, String))

    def analyze
      files = java_files_with_content
      page_mounts = Hash(String, Array(String)).new { |hash, key| hash[key] = [] of String }
      seen = Set(String).new

      files.each do |file|
        collect_mount_path_annotations(file, page_mounts, seen)
        collect_mount_calls(file, page_mounts, seen)
        collect_mapper_mounts(file, page_mounts, seen)
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
        }
      end

      files
    end

    private def collect_mount_path_annotations(file : FileInfo,
                                               page_mounts : Hash(String, Array(String)),
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
          page_mounts[class_name] << normalized unless page_mounts[class_name].includes?(normalized)
          add_endpoint(normalized, file[:path], line_for_offset(content, marker), seen)
        end
      end
    end

    private def collect_mount_calls(file : FileInfo,
                                    page_mounts : Hash(String, Array(String)),
                                    seen : Set(String))
      {"mountPage", "mountPackage", "mountResource"}.each do |method_name|
        scan_method_calls(file[:content], method_name) do |args, offset|
          arguments = split_arguments(args)
          next if arguments.empty?

          mount_path = resolve_string_expression(arguments[0], file[:constants])
          next unless mount_path

          normalized = normalize_mount_path(mount_path)
          endpoint_path = method_name == "mountPackage" ? package_mount_path(normalized) : normalized
          add_endpoint(endpoint_path, file[:path], line_for_offset(file[:content], offset), seen)

          if method_name == "mountPage"
            if page_class = class_literal_name(arguments[1]?)
              page_mounts[page_class] << normalized unless page_mounts[page_class].includes?(normalized)
            end
          end
        end
      end
    end

    private def collect_mapper_mounts(file : FileInfo,
                                      page_mounts : Hash(String, Array(String)),
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
          page_mounts[page_class] << normalized unless page_mounts[page_class].includes?(normalized)
        end
      end
    end

    private def collect_navigation_mounts(file : FileInfo,
                                          page_mounts : Hash(String, Array(String)),
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
                                            page_mounts : Hash(String, Array(String)),
                                            seen : Set(String),
                                            open_idx : Int32,
                                            offset : Int32)
      close_idx = find_matching_paren(file[:content], open_idx)
      return unless close_idx

      args = file[:content][(open_idx + 1)...close_idx]
      emit_page_class_endpoints(file, page_mounts, seen, class_literal_names(args), offset)
    end

    private def emit_page_class_endpoints(file : FileInfo,
                                          page_mounts : Hash(String, Array(String)),
                                          seen : Set(String),
                                          page_classes : Array(String),
                                          offset : Int32)
      page_classes.uniq.each do |page_class|
        page_mounts[page_class]?.try &.each do |mount_path|
          add_endpoint(mount_path, file[:path], line_for_offset(file[:content], offset), seen)
        end
      end
    end

    private def add_endpoint(path : String, file_path : String, line : Int32, seen : Set(String))
      endpoint = Endpoint.new(path, "GET", path_params(path), Details.new(PathInfo.new(file_path, line)))
      key = endpoint_key(endpoint)
      return if seen.includes?(key)

      seen << key
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
      normalized = normalized.gsub(%r{/+}, "/")
      return "/" if normalized.empty?
      normalized.starts_with?("/") ? normalized : "/#{normalized}"
    end

    private def package_mount_path(path : String) : String
      path == "/" ? "/**" : "#{path.rstrip('/')}/**"
    end

    private def next_class_name(content : String, offset : Int32) : String
      rest = content[offset..]? || ""
      if match = rest.match(/\bclass\s+([A-Za-z_][A-Za-z0-9_]*)\b/)
        return match[1]
      end

      ""
    end

    private def resolve_string_expression(expression : String,
                                          constants : Hash(String, String)) : String?
      parts = expression.split('+').map(&.strip).reject(&.empty?)
      return if parts.empty?

      values = parts.compact_map do |part|
        resolve_string_part(part, constants)
      end

      values.size == parts.size ? values.join : nil
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

    private def line_for_offset(content : String, offset : Int32) : Int32
      content[0...offset].count('\n') + 1
    end
  end
end
