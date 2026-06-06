require "../../../models/analyzer"
require "../../engines/java_engine"
require "../../../miniparsers/jvm_lambda_dsl_extractor_ts"

module Analyzer::Java
  # Javalin runs on the lambda-DSL routing style:
  # `app.get("/x", ctx -> ...)` and `path("/api", () -> { ... })`
  # nested via `app.routes(() -> { ... })`. The shared
  # `TreeSitterJvmLambdaDslExtractor` does the heavy lifting; this
  # analyzer just supplies the Javalin method-name set and turns
  # the raw scan results into `Endpoint`s.
  class Javalin < Analyzer
    JAVA_EXTENSION  = "java"
    JAVALIN_MARKERS = ["io.javalin"]

    # Javalin's request-context helpers. `header` and `cookie`
    # double as response setters, but using them with a single
    # string argument is overwhelmingly the read path — false
    # positives here are cheap (a benign extra param to scan).
    CONFIG = Noir::TreeSitterJvmLambdaDslExtractor::Config.new(
      verb_methods: {
        "get"     => "GET",
        "post"    => "POST",
        "put"     => "PUT",
        "delete"  => "DELETE",
        "patch"   => "PATCH",
        "head"    => "HEAD",
        "options" => "OPTIONS",
        "query"   => "QUERY",
        "sse"     => "GET",
      },
      nest_methods: Set{"path"},
      handler_methods: Set{"addHandler", "addHttpHandler"},
      crud_methods: Set{"crud"},
      transparent_methods: Set{"routes", "before", "after"},
      query_methods: Set{"queryParam", "queryParamAsClass", "queryParams"},
      form_methods: Set{"formParam", "formParamAsClass", "formParams", "uploadedFile", "uploadedFiles"},
      header_methods: Set{"header", "headerAsClass"},
      cookie_methods: Set{"cookie"},
      body_methods: Set{"body", "bodyAsBytes", "bodyAsInputStream", "bodyInputStream"},
      body_typed_methods: Set{"bodyAsClass", "bodyValidator", "bodyStreamAsClass"},
      websocket_methods: Set{"ws"},
    )

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)
      file_list = all_files()
      file_list.each do |path|
        next if JavaEngine.test_path?(path)
        next unless File.exists?(path)
        next unless path.ends_with?(".#{JAVA_EXTENSION}")

        content = read_file_content(path)
        next unless JAVALIN_MARKERS.any? { |m| content.includes?(m) }

        context_path = context_path_for(content)
        Noir::TreeSitterJvmLambdaDslExtractor.extract_routes(content, CONFIG, include_callees: include_callee).each do |route|
          @result << build_endpoint(route, path, context_path)
        end

        constants = string_constants_for(content)
        collect_static_file_endpoints(content, constants).each do |entry|
          endpoint_path, line = entry
          @result << Endpoint.new(join_paths(context_path, endpoint_path), "GET", Details.new(PathInfo.new(path, line)))
        end
      end

      Fiber.yield
      @result
    end

    private def build_endpoint(route : Noir::TreeSitterJvmLambdaDslExtractor::Route,
                               path : String,
                               context_path : String) : Endpoint
      params = [] of Param
      route.query_params.each { |name| params << Param.new(name, "", "query") }
      route.form_params.each { |name| params << Param.new(name, "", "form") }
      route.header_params.each { |name| params << Param.new(name, "", "header") }
      route.cookie_params.each { |name| params << Param.new(name, "", "cookie") }
      if route.has_body?
        params << Param.new("body", route.body_type || "", "json")
      end

      details = Details.new(PathInfo.new(path, route.line + 1))
      endpoint = Endpoint.new(join_paths(context_path, route.path), route.verb, params, details)
      endpoint.protocol = route.protocol

      # 1-hop callees out of the handler lambda body. The Route
      # extractor doesn't carry the file path, so attach it here.
      route.callees.each do |entry|
        name, line = entry
        endpoint.push_callee(Callee.new(name, path: path, line: line))
      end

      endpoint
    end

    private def collect_static_file_endpoints(content : String,
                                              constants : Hash(String, String)) : Array(Tuple(String, Int32))
      endpoints = [] of Tuple(String, Int32)
      collect_static_file_add_endpoints(content, constants, endpoints)
      collect_webjar_endpoints(content, endpoints)
      endpoints.uniq
    end

    private def collect_static_file_add_endpoints(content : String,
                                                  constants : Hash(String, String),
                                                  endpoints : Array(Tuple(String, Int32)))
      offset = 0
      while marker = next_static_files_add_marker(content, offset)
        offset = marker + 3
        open_idx = content.index('(', marker)
        next unless open_idx
        close_idx = find_matching_paren(content, open_idx)
        next unless close_idx

        args = content[(open_idx + 1)...close_idx]
        line = content[0...marker].count('\n') + 1
        if hosted_path = hosted_path_from_static_file_config(args, constants)
          endpoints << {static_mount_path(hosted_path), line}
        elsif directory_add_call?(args)
          endpoints << {"/**", line}
        end
      end
    end

    private def collect_webjar_endpoints(content : String,
                                         endpoints : Array(Tuple(String, Int32)))
      offset = 0
      while marker = content.index("enableWeb", offset)
        offset = marker + 9
        next unless enable_webjars_call?(content, marker)
        endpoints << {"/webjars/**", content[0...marker].count('\n') + 1}
      end
    end

    private def next_static_files_add_marker(content : String, offset : Int32) : Int32?
      static_files_marker = content.index(".staticFiles.add", offset)
      add_static_marker = content.index(".addStaticFiles", offset)
      markers = [static_files_marker, add_static_marker].compact
      markers.min?
    end

    private def hosted_path_from_static_file_config(args : String,
                                                    constants : Hash(String, String)) : String?
      args.scan(/\.hostedPath\s*=\s*([^;]+);/) do |match|
        if hosted_path = resolve_string_expression(match[1], constants)
          return hosted_path
        end
      end
      nil
    end

    private def directory_add_call?(args : String) : Bool
      first_arg = first_argument(args).strip
      first_arg.starts_with?('"') || !!(first_arg =~ /\A[A-Za-z_][A-Za-z0-9_.]*\z/)
    end

    private def static_mount_path(hosted_path : String) : String
      normalized = normalize_optional_path(hosted_path)
      normalized.empty? ? "/**" : join_paths(normalized, "**")
    end

    private def context_path_for(content : String) : String
      constants = string_constants_for(content)

      content.scan(/(?:router|routing)\.contextPath\s*=\s*([^;]+);/) do |match|
        if context_path = resolve_string_expression(match[1], constants)
          return normalize_optional_path(context_path)
        end
      end

      content.scan(/\.contextPath\s*\(([^)]*)\)/) do |match|
        if context_path = resolve_string_expression(match[1], constants)
          return normalize_optional_path(context_path)
        end
      end

      ""
    end

    private def string_constants_for(content : String) : Hash(String, String)
      constants = Hash(String, String).new
      Noir::TreeSitter.parse_java(content) do |root|
        constants = Noir::TreeSitterJavaRouteExtractor.extract_string_constants_from(root, content)
      end
      constants
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
      if part.starts_with?('"') && part.ends_with?('"') && part.size >= 2
        return part[1..-2]
      end

      if resolved = constants[part]?
        return resolved
      end

      suffix = ".#{part}"
      matches = constants.compact_map do |key, value|
        key.ends_with?(suffix) ? value : nil
      end.uniq!
      matches.size == 1 ? matches.first : nil
    end

    private def normalize_optional_path(path : String) : String
      trimmed = path.strip
      return "" if trimmed.empty? || trimmed == "/"
      trimmed.starts_with?("/") ? trimmed : "/#{trimmed}"
    end

    private def first_argument(args : String) : String
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
        when '(', '[', '{'
          depth += 1
        when ')', ']', '}'
          depth -= 1 if depth > 0
        when ','
          return args[...index] if depth.zero?
        end
      end

      args
    end

    private def find_matching_paren(code : String, open_idx : Int32) : Int32?
      # Scan by CHARACTER (not byte): open_idx is a char index and the caller
      # char-slices with the returned index. ASCII-identical to the byte loop.
      depth = 1
      in_string = false
      escape = false
      code.each_char_with_index do |char, idx|
        next if idx <= open_idx
        if in_string
          if escape
            escape = false
          elsif char == '\\'
            escape = true
          elsif char == '"'
            in_string = false
          end
        else
          case char
          when '"' then in_string = true
          when '(' then depth += 1
          when ')'
            depth -= 1
            return idx if depth.zero?
          end
        end
      end
      nil
    end

    private def enable_webjars_call?(content : String, marker : Int32) : Bool
      # marker is a CHAR index; use char-based slicing (byte_slice would misread
      # the prefix when a multi-byte char precedes the call). `content[start, n]`
      # clamps at end-of-string instead of raising.
      match =
        if content[marker, 13] == "enableWebjars"
          "enableWebjars"
        elsif content[marker, 13] == "enableWebJars"
          "enableWebJars"
        else
          return false
        end

      after_idx = marker + match.size
      while after_idx < content.size && content[after_idx].ascii_whitespace?
        after_idx += 1
      end
      after_idx < content.size && content[after_idx] == '('
    end

    private def join_paths(prefix : String, suffix : String) : String
      return suffix if prefix.empty?
      return prefix.rstrip('/') if suffix.empty?
      "#{prefix.rstrip('/')}/#{suffix.lstrip('/')}"
    end
  end
end
