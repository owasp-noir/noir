require "../../../models/analyzer"
require "../../../miniparsers/dart_callee_extractor"
require "./dart_helper"

module Analyzer::Dart
  # dart:io's HttpServer is Dart's built-in HTTP server surface. It has
  # no declarative router, so routes are usually guards over
  # `HttpRequest.method` and `HttpRequest.uri.path` inside an `await for`
  # or `listen` handler.
  class Http < Analyzer
    DART_IO_IMPORT_RE = /^\s*import\s+['"]dart:io['"]/m
    HTTP_METHODS      = "GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE"

    METHOD_COMPARE_RE   = /\b([A-Za-z_]\w*)\s*\.\s*method\s*==\s*r?["'](#{HTTP_METHODS})["']/
    REVERSE_METHOD_RE   = /r?["'](#{HTTP_METHODS})["']\s*==\s*\b([A-Za-z_]\w*)\s*\.\s*method/
    PATH_COMPARE_RE     = /\b([A-Za-z_]\w*)\s*\.\s*uri\s*\.\s*path\s*==\s*r?["']([^"']+?)["']/
    REVERSE_PATH_RE     = /r?["']([^"']+?)["']\s*==\s*\b([A-Za-z_]\w*)\s*\.\s*uri\s*\.\s*path/
    PATH_STARTS_WITH_RE = /\b([A-Za-z_]\w*)\s*\.\s*uri\s*\.\s*path\s*\.\s*startsWith\s*\(\s*r?["']([^"']+?)["']/
    PATH_CASE_RE        = /(?:^|[^\w.])case\s+r?["']([^"']+?)["']\s*:/
    METHOD_CASE_RE      = /(?:^|[^\w.])case\s+r?["'](#{HTTP_METHODS})["']\s*:/
    SWITCH_PATH_RE      = /\bswitch\s*\([^\)]*\.\s*uri\s*\.\s*path\s*\)/
    SWITCH_METHOD_RE    = /\bswitch\s*\([^\)]*\.\s*method\s*\)/
    QUERY_PARAM_RE      = /\.uri\s*\.\s*queryParameters(?:All)?\s*\[\s*r?["']([^"']+?)["']\s*\]/
    HEADER_VALUE_RE     = /\.headers\s*\.\s*value\s*\(\s*r?["']([^"']+?)["']/
    HEADER_INDEX_RE     = /\.headers\s*\[\s*r?["']([^"']+?)["']\s*\]/
    COOKIE_NAME_RE      = /\.cookies\b.*?\.name\s*==\s*r?["']([^"']+?)["']/
    BODY_READ_RE        = /utf8\s*\.\s*decoder\s*\.\s*bind\s*\([^\)]*\)|\.transform\s*\(\s*utf8\s*\.\s*decoder\s*\)|jsonDecode\s*\(/

    alias MethodContext = NamedTuple(method: String, depth: Int32, params: Array(Param), switch_case: Bool)
    alias PathContext = NamedTuple(path: String, depth: Int32, params: Array(Param), switch_case: Bool)
    alias RouteContext = NamedTuple(endpoints: Array(Endpoint), depth: Int32)
    alias SwitchContext = NamedTuple(depth: Int32)

    def analyze
      include_callee = callees_needed?
      mutex = Mutex.new
      endpoints = [] of Endpoint

      begin
        files = get_files_by_extension(".dart")
        parallel_analyze(files) do |path|
          next unless path.ends_with?(".dart")
          next if Helper.test_path?(path, base_paths)

          content = begin
            read_file_content(path)
          rescue e
            logger.debug "Error reading #{path}: #{e.message}"
            next
          end

          next unless http_file?(content)

          found = scan_file(content, path, include_callee)
          next if found.empty?

          mutex.synchronize { endpoints.concat(found) }
        end
      rescue e
        logger.debug e
      end

      endpoints
    end

    private def http_file?(content : String) : Bool
      return false unless content.match(DART_IO_IMPORT_RE)
      content.includes?("HttpServer") || content.includes?("HttpRequest")
    end

    private def scan_file(content : String, path : String, include_callee : Bool) : Array(Endpoint)
      cleaned = Helper.strip_comments(content)
      lines = cleaned.lines
      offsets = line_offsets(content)
      endpoints = [] of Endpoint
      seen = Set(String).new
      method_contexts = [] of MethodContext
      path_contexts = [] of PathContext
      route_contexts = [] of RouteContext
      method_switches = [] of SwitchContext
      path_switches = [] of SwitchContext
      brace_depth = 0

      lines.each_with_index do |line, index|
        scan_depth = brace_depth - leading_closing_braces(line)
        scan_depth = 0 if scan_depth < 0

        pop_contexts(method_contexts, scan_depth)
        pop_contexts(path_contexts, scan_depth)
        pop_route_contexts(route_contexts, scan_depth)
        pop_switches(method_switches, scan_depth)
        pop_switches(path_switches, scan_depth)

        guard_method = method_from_line(line)
        case_method = method_case_from_line(line, !method_switches.empty?)
        replace_method_switch_context(method_contexts, method_switches.last[:depth], case_method) if case_method && !method_switches.empty?

        case_paths = path_cases_from_line(line, !path_switches.empty?)
        replace_path_switch_context(path_contexts, path_switches.last[:depth], case_paths) if !case_paths.empty? && !path_switches.empty?

        line_method = guard_method || case_method
        current_method = line_method || method_contexts.last?.try &.[:method]
        current_path = path_contexts.last?.try &.[:path]
        paths = paths_from_line(line, !path_switches.empty?)
        next_depth = brace_depth + brace_delta(line)
        next_depth = 0 if next_depth < 0
        scoped_path_with_inner_methods = current_method.nil? &&
                                         !paths.empty? &&
                                         opens_scope?(line, scan_depth, next_depth) &&
                                         block_contains_method?(lines, index, next_depth)

        routes = [] of Tuple(String, String)
        if current_path && line_method
          routes << {current_path, line_method}
        end

        unless scoped_path_with_inner_methods
          paths.each do |route_path|
            routes << {route_path, current_method || "GET"}
          end
        end

        new_endpoints = [] of Endpoint
        routes.each do |route_path, method|
          normalized = normalize_path(route_path)
          next unless valid_route_path?(normalized)

          key = "#{method}:#{normalized}:#{index + 1}"
          next if seen.includes?(key)
          seen.add(key)

          callees = include_callee ? callees_for_line(content, offsets[index]? || 0, path) : [] of Noir::DartCalleeExtractor::Entry
          endpoint = build_endpoint(normalized, method, path, index + 1, inherited_params(method_contexts, path_contexts), callees)
          endpoints << endpoint
          new_endpoints << endpoint
        end

        line_params = params_from_line(line)
        attach_or_defer_params(line_params, new_endpoints, route_contexts, method_contexts, path_contexts)

        if opens_scope?(line, scan_depth, next_depth)
          if guard_method
            method_contexts << {method: guard_method, depth: next_depth, params: [] of Param, switch_case: false}
          end
          paths.each do |route_path|
            normalized = normalize_path(route_path)
            path_contexts << {path: normalized, depth: next_depth, params: [] of Param, switch_case: false} if valid_route_path?(normalized)
          end
          if !new_endpoints.empty?
            route_contexts << {endpoints: new_endpoints, depth: next_depth}
          end
          if line.matches?(SWITCH_METHOD_RE)
            method_switches << {depth: next_depth}
          end
          if line.matches?(SWITCH_PATH_RE)
            path_switches << {depth: next_depth}
          end
        end

        brace_depth = next_depth
      end

      endpoints
    end

    private def method_from_line(line : String) : String?
      if match = line.match(METHOD_COMPARE_RE)
        return match[2]
      end
      if match = line.match(REVERSE_METHOD_RE)
        return match[1]
      end
      nil
    end

    private def method_case_from_line(line : String, in_method_switch : Bool) : String?
      return unless in_method_switch
      if match = line.match(METHOD_CASE_RE)
        return match[1]
      end
      nil
    end

    private def paths_from_line(line : String, in_path_switch : Bool) : Array(String)
      paths = [] of String

      line.scan(PATH_COMPARE_RE) do |match|
        paths << match[2]
      end
      line.scan(REVERSE_PATH_RE) do |match|
        paths << match[1]
      end
      line.scan(PATH_STARTS_WITH_RE) do |match|
        paths << match[2]
      end
      if in_path_switch
        line.scan(PATH_CASE_RE) do |match|
          paths << match[1]
        end
      end

      paths.uniq
    end

    private def path_cases_from_line(line : String, in_path_switch : Bool) : Array(String)
      paths = [] of String
      return paths unless in_path_switch

      line.scan(PATH_CASE_RE) do |match|
        paths << match[1]
      end

      paths.uniq
    end

    private def block_contains_method?(lines : Array(String), start_index : Int32, context_depth : Int32) : Bool
      depth = context_depth
      index = start_index + 1

      while index < lines.size
        line = lines[index]
        scan_depth = depth - leading_closing_braces(line)
        scan_depth = 0 if scan_depth < 0
        return false if scan_depth < context_depth
        return true if method_from_line(line) || line.matches?(SWITCH_METHOD_RE) || line.matches?(METHOD_CASE_RE)

        depth += brace_delta(line)
        depth = 0 if depth < 0
        index += 1
      end

      false
    end

    private def params_from_line(line : String) : Array(Param)
      params = [] of Param
      line.scan(QUERY_PARAM_RE) do |match|
        append_param(params, Param.new(match[1], "", "query"))
      end
      line.scan(HEADER_VALUE_RE) do |match|
        append_param(params, Param.new(match[1], "", "header"))
      end
      line.scan(HEADER_INDEX_RE) do |match|
        append_param(params, Param.new(match[1], "", "header"))
      end
      line.scan(COOKIE_NAME_RE) do |match|
        append_param(params, Param.new(match[1], "", "cookie"))
      end
      if line.matches?(BODY_READ_RE)
        append_param(params, Param.new("body", "", "json"))
      end

      params
    end

    private def append_param(params : Array(Param), param : Param)
      return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
      params << param
    end

    private def attach_or_defer_params(params : Array(Param),
                                       new_endpoints : Array(Endpoint),
                                       route_contexts : Array(RouteContext),
                                       method_contexts : Array(MethodContext),
                                       path_contexts : Array(PathContext))
      return if params.empty?

      if !new_endpoints.empty?
        attach_params(new_endpoints, params)
      elsif route_context = route_contexts.last?
        attach_params(route_context[:endpoints], params)
      elsif method_context = method_contexts.last?
        append_params(method_context[:params], params)
      elsif path_context = path_contexts.last?
        append_params(path_context[:params], params)
      end
    end

    private def attach_params(endpoints : Array(Endpoint), params : Array(Param))
      endpoints.each do |endpoint|
        params.each do |param|
          endpoint.push_param(param)
        end
      end
    end

    private def append_params(target : Array(Param), params : Array(Param))
      params.each do |param|
        append_param(target, param)
      end
    end

    private def inherited_params(method_contexts : Array(MethodContext), path_contexts : Array(PathContext)) : Array(Param)
      params = [] of Param
      method_contexts.each { |context| append_params(params, context[:params]) }
      path_contexts.each { |context| append_params(params, context[:params]) }
      params
    end

    private def build_endpoint(url : String,
                               method : String,
                               path : String,
                               line : Int32,
                               inherited_params : Array(Param),
                               callees : Array(Noir::DartCalleeExtractor::Entry)) : Endpoint
      endpoint = Endpoint.new(url, method)
      endpoint.details = Details.new(PathInfo.new(path, line))
      inherited_params.each do |param|
        endpoint.push_param(param)
      end
      url.scan(/\{(\w+)\}/) do |match|
        endpoint.push_param(Param.new(match[1], "", "path"))
      end
      Noir::DartCalleeExtractor.attach_to(endpoint, callees)
      endpoint
    end

    private def normalize_path(route_path : String) : String
      path = route_path.split("?", 2).first
      path = path.split("#", 2).first
      path = "/#{path}" unless path.starts_with?("/")
      path = path.gsub(/\/+/, "/")
      path = path[0...-1] if path.ends_with?("/") && path != "/"
      path = path.gsub(/\$\{([A-Za-z_]\w*)\}/) { "{#{$1}}" }
      path = path.gsub(/\$([A-Za-z_]\w*)/) { "{#{$1}}" }
      path.empty? ? "/" : path
    end

    private def valid_route_path?(path : String) : Bool
      return false if path.empty?
      return false unless path.starts_with?("/")
      return false if path.includes?(" ")
      path.size <= 200
    end

    private def callees_for_line(content : String, line_start : Int32, path : String) : Array(Noir::DartCalleeExtractor::Entry)
      line_end = content.index('\n', line_start) || content.bytesize
      body_info = Noir::DartCalleeExtractor.extract_body_after(content, line_start, line_end)
      return [] of Noir::DartCalleeExtractor::Entry unless body_info

      body, body_start, _ = body_info
      start_line = Noir::DartCalleeExtractor.line_number_for(content, body_start)
      Noir::DartCalleeExtractor.callees_for_body(body, path, start_line)
    end

    private def line_offsets(content : String) : Array(Int32)
      offsets = [] of Int32
      offset = 0
      content.each_line(chomp: false) do |line|
        offsets << offset
        offset += line.bytesize
      end
      offsets
    end

    private def pop_contexts(contexts : Array(MethodContext), depth : Int32)
      contexts.reject! { |context| context[:depth] > depth }
    end

    private def pop_contexts(contexts : Array(PathContext), depth : Int32)
      contexts.reject! { |context| context[:depth] > depth }
    end

    private def pop_route_contexts(contexts : Array(RouteContext), depth : Int32)
      contexts.reject! { |context| context[:depth] > depth }
    end

    private def pop_switches(contexts : Array(SwitchContext), depth : Int32)
      contexts.reject! { |context| context[:depth] > depth }
    end

    private def replace_method_switch_context(contexts : Array(MethodContext), depth : Int32, method : String)
      contexts.reject! { |context| context[:switch_case] && context[:depth] == depth }
      contexts << {method: method, depth: depth, params: [] of Param, switch_case: true}
    end

    private def replace_path_switch_context(contexts : Array(PathContext), depth : Int32, paths : Array(String))
      contexts.reject! { |context| context[:switch_case] && context[:depth] == depth }
      paths.each do |route_path|
        normalized = normalize_path(route_path)
        contexts << {path: normalized, depth: depth, params: [] of Param, switch_case: true} if valid_route_path?(normalized)
      end
    end

    private def opens_scope?(line : String, current_depth : Int32, next_depth : Int32) : Bool
      next_depth > current_depth && line.includes?("{")
    end

    private def leading_closing_braces(line : String) : Int32
      count = 0
      line.each_char do |char|
        if char.whitespace?
          next
        elsif char == '}'
          count += 1
        else
          break
        end
      end
      count
    end

    private def brace_delta(line : String) : Int32
      delta = 0
      in_string = false
      quote = '\0'
      escaped = false

      line.each_char do |char|
        if escaped
          escaped = false
          next
        end

        if in_string
          if char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
          next
        end

        case char
        when '"', '\''
          in_string = true
          quote = char
        when '{'
          delta += 1
        when '}'
          delta -= 1
        end
      end

      delta
    end
  end
end
