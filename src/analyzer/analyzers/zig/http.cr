require "../../../models/analyzer"
require "../../../miniparsers/zig_callee_extractor"

module Analyzer::Zig
  # Zig's standard `std.http.Server` has no routing DSL. Applications usually
  # branch on `request.head.target` and `request.head.method` after
  # `receiveHead()`, then call `request.respond(...)` or a handler function.
  class Http < Analyzer
    TARGET_ASSIGN_RE = /(?:const|var)\s+([A-Za-z_]\w*)\s*(?::\s*[^=;]+)?=\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*;/

    TARGET_EQL_RE      = /std\s*\.\s*mem\s*\.\s*eql\s*\(\s*u8\s*,\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)/
    PATH_EQL_RE        = /std\s*\.\s*mem\s*\.\s*eql\s*\(\s*u8\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*\)/
    TARGET_EQUALS_RE   = /([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*==\s*"((?:[^"\\]|\\.)*)"/
    PATH_EQUALS_RE     = /"((?:[^"\\]|\\.)*)"\s*==\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)/
    METHOD_EQUALS_RE   = /([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*==\s*\.([A-Za-z_]\w*)/
    METHOD_REVERSED_RE = /\.([A-Za-z_]\w*)\s*==\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)/
    SWITCH_RE          = /switch\s*\(\s*([A-Za-z_]\w*(?:\s*\.\s*[A-Za-z_]\w*)*)\s*\)\s*\{/
    SWITCH_PRONG_RE    = /\.([A-Za-z_]\w*)\s*=>\s*\{/
    TARGET_PRONG_RE    = /"((?:[^"\\]|\\.)*)"\s*=>/
    IF_RE              = /(?:^|[^A-Za-z0-9_])if\s*\(/

    alias IfBlock = NamedTuple(cond_start: Int32, cond_end: Int32, body_open: Int32, body_close: Int32)
    alias MethodContext = NamedTuple(method: String, body_open: Int32, body_close: Int32)
    alias RouteHit = NamedTuple(url: String, offset: Int32)
    alias RouteBlock = NamedTuple(url: String, offset: Int32, body_start: Int32, body_end: Int32)

    def analyze
      include_callee = callees_needed?

      all_files.each do |path|
        next unless path.ends_with?(".zig")
        next if Noir::ZigCalleeExtractor.vendored_framework_path?(path)
        content = read_file_content(path)
        next unless std_http_server_file?(content)
        process_file(path, content, include_callee)
      end

      @result
    end

    private def std_http_server_file?(content : String) : Bool
      return true if content.includes?("std.http.Server")

      has_std = content.includes?("@import(\"std\")") || content.includes?("std.http")
      has_server_flow = content.includes?(".receiveHead(") && content.includes?(".head.target")
      has_response = content.includes?(".respond(")

      has_std && has_server_flow && has_response
    end

    private def process_file(path : String, content : String, include_callee : Bool)
      text = Noir::ZigCalleeExtractor.strip_comments(content)
      stripped = Noir::ZigCalleeExtractor.strip_non_code(content)
      chars = stripped.chars
      test_blocks = Noir::ZigCalleeExtractor.test_block_ranges(stripped)
      target_vars = aliases_for(text, ".head.target")
      method_vars = aliases_for(text, ".head.method")
      if_blocks = collect_if_blocks(stripped, chars)
      method_contexts = collect_method_contexts(stripped, chars, if_blocks, method_vars)
      seen = Set(String).new

      collect_route_hits(text, target_vars).each do |hit|
        offset = hit[:offset]
        next if Noir::ZigCalleeExtractor.in_test_block?(offset, test_blocks)
        branch = if_blocks.find { |block| offset >= block[:cond_start] && offset <= block[:cond_end] }
        next if branch.nil?

        condition = slice(chars, branch[:cond_start], branch[:cond_end])
        method = method_from_condition(condition, method_vars) || method_from_context(offset, method_contexts) || "GET"
        key = "#{method} #{hit[:url]}"
        next if seen.includes?(key)
        seen << key

        emit_range(path, text, chars, hit[:offset], hit[:url], method, branch[:body_open] + 1, branch[:body_close], include_callee)
      end

      collect_target_switch_routes(text, stripped, chars, target_vars).each do |route|
        offset = route[:offset]
        next if Noir::ZigCalleeExtractor.in_test_block?(offset, test_blocks)
        route_method_contexts = method_contexts.select do |context|
          context[:body_open] >= route[:body_start] && context[:body_close] <= route[:body_end]
        end

        if route_method_contexts.empty?
          method = method_from_context(offset, method_contexts) || "GET"
          key = "#{method} #{route[:url]}"
          next if seen.includes?(key)
          seen << key

          emit_range(path, text, chars, offset, route[:url], method, route[:body_start], route[:body_end], include_callee)
        else
          route_method_contexts.each do |context|
            method = context[:method]
            key = "#{method} #{route[:url]}"
            next if seen.includes?(key)
            seen << key

            emit_range(path, text, chars, offset, route[:url], method, context[:body_open] + 1, context[:body_close], include_callee)
          end
        end
      end
    end

    private def aliases_for(text : String, suffix : String) : Set(String)
      aliases = Set(String).new
      changed = true

      while changed
        changed = false
        text.scan(TARGET_ASSIGN_RE) do |m|
          name = m[1]
          expr = normalize_expr(m[2])
          next unless expr.ends_with?(suffix) || aliases.includes?(expr)
          next if aliases.includes?(name)
          aliases << name
          changed = true
        end
      end

      aliases
    end

    private def collect_route_hits(text : String, target_vars : Set(String)) : Array(RouteHit)
      hits = [] of RouteHit

      text.scan(TARGET_EQL_RE) do |m|
        next unless target_expr?(m[1], target_vars)
        add_route_hit(hits, m[2], m.begin(0) || 0)
      end

      text.scan(PATH_EQL_RE) do |m|
        next unless target_expr?(m[2], target_vars)
        add_route_hit(hits, m[1], m.begin(0) || 0)
      end

      text.scan(TARGET_EQUALS_RE) do |m|
        next unless target_expr?(m[1], target_vars)
        add_route_hit(hits, m[2], m.begin(0) || 0)
      end

      text.scan(PATH_EQUALS_RE) do |m|
        next unless target_expr?(m[2], target_vars)
        add_route_hit(hits, m[1], m.begin(0) || 0)
      end

      hits
    end

    private def collect_target_switch_routes(text : String, stripped : String, chars : Array(Char), target_vars : Set(String)) : Array(RouteBlock)
      routes = [] of RouteBlock

      stripped.scan(SWITCH_RE) do |m|
        expr = m[1]
        next unless target_expr?(expr, target_vars)
        switch_open = (m.end(0) || 0) - 1
        switch_close = Noir::ZigCalleeExtractor.find_matching(chars, switch_open, '{', '}')
        next if switch_close.nil?

        switch_body = slice(text.chars, switch_open + 1, switch_close)
        switch_body.scan(TARGET_PRONG_RE) do |pm|
          url = unescape_string(pm[1])
          next unless url.starts_with?("/")

          literal_offset = switch_open + 1 + (pm.begin(1) || 0) - 1
          expr_start = next_non_space(chars, switch_open + 1 + (pm.end(0) || 0))
          next if expr_start.nil?

          if chars[expr_start] == '{'
            body_close = Noir::ZigCalleeExtractor.find_matching(chars, expr_start, '{', '}')
            next if body_close.nil?
            routes << {url: url, offset: literal_offset, body_start: expr_start + 1, body_end: body_close}
          else
            body_end = switch_prong_expression_end(chars, expr_start, switch_close)
            routes << {url: url, offset: literal_offset, body_start: expr_start, body_end: body_end}
          end
        end
      end

      routes
    end

    private def add_route_hit(hits : Array(RouteHit), raw_url : String, offset : Int32)
      url = unescape_string(raw_url)
      return unless url.starts_with?("/")
      hits << {url: url, offset: offset}
    end

    private def collect_if_blocks(stripped : String, chars : Array(Char)) : Array(IfBlock)
      blocks = [] of IfBlock

      stripped.scan(IF_RE) do |m|
        open_paren = (m.end(0) || 0) - 1
        close_paren = Noir::ZigCalleeExtractor.find_matching(chars, open_paren, '(', ')')
        next if close_paren.nil?
        body_open = next_block_brace(chars, close_paren + 1)
        next if body_open.nil?
        body_close = Noir::ZigCalleeExtractor.find_matching(chars, body_open, '{', '}')
        next if body_close.nil?

        blocks << {
          cond_start: open_paren + 1,
          cond_end:   close_paren,
          body_open:  body_open,
          body_close: body_close,
        }
      end

      blocks
    end

    private def collect_method_contexts(stripped : String, chars : Array(Char), if_blocks : Array(IfBlock), method_vars : Set(String)) : Array(MethodContext)
      contexts = [] of MethodContext

      if_blocks.each do |block|
        condition = slice(chars, block[:cond_start], block[:cond_end])
        if method = method_from_condition(condition, method_vars)
          contexts << {method: method, body_open: block[:body_open], body_close: block[:body_close]}
        end
      end

      stripped.scan(SWITCH_RE) do |m|
        expr = m[1]
        next unless method_expr?(expr, method_vars)
        switch_open = (m.end(0) || 0) - 1
        switch_close = Noir::ZigCalleeExtractor.find_matching(chars, switch_open, '{', '}')
        next if switch_close.nil?

        switch_body = slice(chars, switch_open + 1, switch_close)
        switch_body.scan(SWITCH_PRONG_RE) do |pm|
          body_open = switch_open + 1 + (pm.end(0) || 0) - 1
          body_close = Noir::ZigCalleeExtractor.find_matching(chars, body_open, '{', '}')
          next if body_close.nil?
          contexts << {method: normalize_method(pm[1]), body_open: body_open, body_close: body_close}
        end
      end

      contexts
    end

    private def method_from_condition(condition : String, method_vars : Set(String)) : String?
      condition.scan(METHOD_EQUALS_RE) do |m|
        next unless method_expr?(m[1], method_vars)
        return normalize_method(m[2])
      end

      condition.scan(METHOD_REVERSED_RE) do |m|
        next unless method_expr?(m[2], method_vars)
        return normalize_method(m[1])
      end

      nil
    end

    private def method_from_context(offset : Int32, contexts : Array(MethodContext)) : String?
      best = nil.as(MethodContext?)

      contexts.each do |context|
        next unless offset > context[:body_open] && offset < context[:body_close]
        if current = best
          next unless (context[:body_close] - context[:body_open]) < (current[:body_close] - current[:body_open])
        end

        best = context
      end

      if selected = best
        selected[:method]
      end
    end

    private def emit_range(path : String, text : String, chars : Array(Char), offset : Int32, url : String, method : String, body_start : Int32, body_end : Int32, include_callee : Bool)
      line = Noir::ZigCalleeExtractor.line_at(text.chars, offset)
      endpoint = Endpoint.new(url, method, extract_path_params(url), Details.new(PathInfo.new(path, line)))

      if include_callee
        body = slice(chars, body_start, body_end)
        body_line = Noir::ZigCalleeExtractor.line_at(chars, body_start)
        callees = Noir::ZigCalleeExtractor.callees_for_body(body, path, body_line)
        Noir::ZigCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
      end

      @result << endpoint
    end

    private def target_expr?(expr : String, target_vars : Set(String)) : Bool
      normalized = normalize_expr(expr)
      normalized.ends_with?(".head.target") || target_vars.includes?(normalized)
    end

    private def method_expr?(expr : String, method_vars : Set(String)) : Bool
      normalized = normalize_expr(expr)
      normalized.ends_with?(".head.method") || method_vars.includes?(normalized)
    end

    private def normalize_expr(expr : String) : String
      expr.gsub(/\s+/, "")
    end

    private def normalize_method(method : String) : String
      method.upcase
    end

    private def next_block_brace(chars : Array(Char), from : Int32) : Int32?
      i = from
      n = chars.size

      while i < n
        ch = chars[i]
        return i if ch == '{'
        return if ch == ';'
        i += 1
      end

      nil
    end

    private def next_non_space(chars : Array(Char), from : Int32) : Int32?
      i = from
      n = chars.size

      while i < n
        return i unless chars[i].whitespace?
        i += 1
      end

      nil
    end

    private def switch_prong_expression_end(chars : Array(Char), from : Int32, switch_close : Int32) : Int32
      paren_depth = 0
      bracket_depth = 0
      brace_depth = 0
      i = from

      while i < switch_close
        case chars[i]
        when '('
          paren_depth += 1
        when ')'
          paren_depth -= 1 if paren_depth > 0
        when '['
          bracket_depth += 1
        when ']'
          bracket_depth -= 1 if bracket_depth > 0
        when '{'
          brace_depth += 1
        when '}'
          brace_depth -= 1 if brace_depth > 0
        when ','
          return i if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0
        end
        i += 1
      end

      switch_close
    end

    private def extract_path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/:([A-Za-z_]\w*)/) do |m|
        params << Param.new(m[1], "", "path")
      end
      params
    end

    private def unescape_string(value : String) : String
      value.gsub("\\\"", "\"").gsub("\\\\", "\\")
    end

    private def slice(chars : Array(Char), start : Int32, stop : Int32) : String
      return "" if start >= stop

      String.build do |io|
        idx = start
        while idx < stop && idx < chars.size
          io << chars[idx]
          idx += 1
        end
      end
    end
  end
end
