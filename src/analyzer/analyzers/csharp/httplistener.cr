require "../../../models/analyzer"
require "./common"

module Analyzer::CSharp
  # System.Net.HttpListener is the .NET BCL built-in HTTP server. It has no
  # route registration API: handlers inspect HttpListenerRequest.HttpMethod and
  # Url/RawUrl at runtime. This analyzer therefore extracts endpoints from
  # conservative request method + path guards in HttpListener handler code.
  class HttpListener < Analyzer
    include Common

    HTTP_METHODS = Set{
      "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "TRACE",
    }
    BODY_METHODS = Set{"POST", "PUT", "PATCH", "DELETE"}

    METHOD_LITERAL_RE = /@?"([A-Za-z]+)"/
    STRING_LITERAL_RE = /@?"([^"]*)"/

    private class BranchContext
      property depth : Int32
      property methods : Array(String)
      property paths : Array(String)

      def initialize(@depth : Int32, @methods : Array(String), @paths : Array(String))
      end
    end

    private class SwitchContext
      property kind : String
      property depth : Int32
      property methods : Array(String)
      property paths : Array(String)

      def initialize(@kind : String, @depth : Int32)
        @methods = [] of String
        @paths = [] of String
      end
    end

    def analyze
      include_callee = callees_needed?

      get_files_by_extension(".cs").each do |file|
        next unless File.exists?(file)
        next if Common.csharp_test_path?(file)

        content = read_file_content(file)
        next unless httplistener_related_source?(content)

        analyze_file(file, content, include_callee)
      end

      @result
    end

    private def httplistener_related_source?(content : String) : Bool
      return true if content.includes?("HttpListener")
      content.includes?("HttpMethod") &&
        (content.includes?("AbsolutePath") || content.includes?("LocalPath") ||
          content.includes?("PathAndQuery") || content.includes?("RawUrl"))
    end

    private def analyze_file(file : String, content : String, include_callee : Bool)
      # Lex once: `tokens` locates comment spans (to strip comments while keeping
      # string literals for text extraction) and `masked_lines` blanks
      # strings/comments/chars for structural brace counting. Both views come
      # from the same scan, so we avoid lexing the source twice.
      lexer = Noir::CSharpLexer.new(content)
      clean_source = strip_comments_preserving_strings(content, lexer)
      clean_lines = clean_source.lines
      masked_lines = lexer.masked_lines
      method_vars, path_vars = extract_request_aliases(clean_lines)

      branch_stack = [] of BranchContext
      switch_stack = [] of SwitchContext
      pending_branch : BranchContext? = nil
      pending_switch_kind : String? = nil
      brace_depth = 0

      clean_lines.each_with_index do |line, index|
        masked = masked_lines[index]? || ""
        brace_delta = masked.count('{') - masked.count('}')
        depth_after = brace_depth + brace_delta

        branch_stack.reject! { |ctx| brace_depth < ctx.depth }
        switch_stack.reject! { |ctx| brace_depth < ctx.depth }

        unless masked.strip.empty?
          if kind = pending_switch_kind
            if masked.includes?("{")
              switch_stack << SwitchContext.new(kind, block_depth(brace_depth, depth_after))
            end
            pending_switch_kind = nil
          end

          if pending = pending_branch
            if masked.includes?("{")
              pending.depth = block_depth(brace_depth, depth_after)
              branch_stack << pending
            end
            pending_branch = nil
          end
        end

        tuple_candidates = extract_tuple_case_candidates(line)
        tuple_candidates.each do |method, route|
          emit_endpoint(file, index, route, method, clean_lines, masked_lines, include_callee)
        end

        case_methods = [] of String
        case_paths = [] of String
        path_from_case = false
        stripped_case = line.lstrip
        if stripped_case.starts_with?("default")
          if current = switch_stack.last?
            current.methods = [] of String
            current.paths = [] of String
          end
        elsif stripped_case.starts_with?("case ")
          if current = switch_stack.last?
            case current.kind
            when "method"
              case_methods = extract_method_literals(line)
              current.methods = case_methods unless case_methods.empty?
            when "path"
              case_paths = extract_path_literals(line, path_vars, allow_without_signal: true)
              unless case_paths.empty?
                current.paths = case_paths
                path_from_case = true
              end
            end
          end
        end

        line_methods = case_methods.empty? ? extract_methods(line, method_vars) : case_methods
        line_paths = case_paths.empty? ? extract_paths(line, path_vars) : case_paths
        active_methods, active_paths = active_request_context(branch_stack, switch_stack)

        if should_emit_from_line?(line_methods, line_paths, active_paths)
          methods = line_methods.empty? ? active_methods : line_methods
          paths = line_paths.empty? ? active_paths : line_paths

          if methods.empty? && !paths.empty?
            if path_from_case && case_block_has_method_guard?(clean_lines, masked_lines, index, method_vars)
              methods = [] of String
            else
              methods = ["GET"]
            end
          end

          paths.each do |route|
            methods.each do |method|
              emit_endpoint(file, index, route, method, clean_lines, masked_lines, include_callee)
            end
          end
        end

        if switch_kind = switch_kind_for(line, method_vars, path_vars)
          if masked.includes?("{")
            switch_stack << SwitchContext.new(switch_kind, block_depth(brace_depth, depth_after))
          else
            pending_switch_kind = switch_kind
          end
        end

        if control_guard_line?(line) && (!line_methods.empty? || !line_paths.empty?)
          context = BranchContext.new(0, line_methods.uniq, line_paths.uniq)
          if masked.includes?("{")
            context.depth = block_depth(brace_depth, depth_after)
            branch_stack << context
          else
            pending_branch = context
          end
        end

        brace_depth = depth_after
      end
    rescue e
      logger.debug "csharp httplistener: failed to analyze #{file}: #{e.message}"
    end

    private def strip_comments_preserving_strings(source : String, lexer : Noir::CSharpLexer) : String
      chars = source.chars
      lexer.tokens.each do |token|
        next unless token.kind == :comment

        (token.start...token.end).each do |idx|
          chars[idx] = chars[idx] == '\n' ? '\n' : ' '
        end
      end
      chars.join
    end

    private def extract_request_aliases(lines : Array(String)) : Tuple(Array(String), Array(String))
      method_vars = [] of String
      path_vars = [] of String

      lines.each do |line|
        next unless line.includes?("=")

        if line.includes?("HttpMethod")
          if var = assignment_lhs_variable(line)
            method_vars << var unless method_vars.includes?(var)
          end
        end

        if path_expression?(line)
          if var = assignment_lhs_variable(line)
            path_vars << var unless path_vars.includes?(var)
          end
        end
      end

      {method_vars, path_vars}
    end

    private def assignment_lhs_variable(line : String) : String?
      if match = line.match(/\b(?:var|string|String)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=/)
        match[1]
      elsif match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[^=]/)
        match[1]
      end
    end

    private def path_expression?(text : String) : Bool
      text.includes?("AbsolutePath") ||
        text.includes?("LocalPath") ||
        text.includes?("PathAndQuery") ||
        text.includes?("RawUrl")
    end

    private def method_signal?(text : String, method_vars : Array(String)) : Bool
      return true if text.includes?("HttpMethod")
      method_vars.any? { |var| text.matches?(/\b#{Regex.escape(var)}\b/) }
    end

    private def path_signal?(text : String, path_vars : Array(String)) : Bool
      return true if path_expression?(text)
      return true if text.includes?(".Url")
      path_vars.any? { |var| text.matches?(/\b#{Regex.escape(var)}\b/) }
    end

    private def extract_methods(line : String, method_vars : Array(String)) : Array(String)
      return [] of String unless method_signal?(line, method_vars)
      extract_method_literals(line)
    end

    private def extract_method_literals(text : String) : Array(String)
      methods = [] of String
      text.scan(METHOD_LITERAL_RE) do |match|
        method = match[1].upcase
        methods << method if HTTP_METHODS.includes?(method) && !methods.includes?(method)
      end
      methods
    end

    private def extract_paths(line : String, path_vars : Array(String)) : Array(String)
      extract_path_literals(line, path_vars, allow_without_signal: false)
    end

    private def extract_path_literals(line : String, path_vars : Array(String), *, allow_without_signal : Bool) : Array(String)
      return [] of String unless allow_without_signal || path_signal?(line, path_vars)
      return [] of String unless allow_without_signal || path_guard_line?(line)

      paths = [] of String
      line.scan(STRING_LITERAL_RE) do |match|
        literal = match[1]
        next unless looks_like_route_path?(literal)

        route = normalize_route_path(literal)
        paths << route unless paths.includes?(route)
      end
      paths
    end

    private def path_guard_line?(line : String) : Bool
      stripped = line.lstrip
      return true if stripped.starts_with?("if") || stripped.starts_with?("else if")
      return true if stripped.starts_with?("case ")
      return true if line.includes?("==") || line.includes?("!=")
      return true if line.includes?(".Equals") || line.includes?(".StartsWith")
      return true if line.includes?(".Contains")
      false
    end

    private def looks_like_route_path?(path : String) : Bool
      return false if path.empty?
      return false unless path.starts_with?("/")
      return false if path.includes?(" ")
      return false if path.size > 240
      true
    end

    private def normalize_route_path(path : String) : String
      normalized = path.split("?", 2).first
      normalized = normalized.split("#", 2).first
      normalized = "/" + normalized unless normalized.starts_with?("/")
      normalized = normalized.gsub(/\/+/, "/")
      normalized = normalized[0...-1] if normalized.ends_with?("/") && normalized != "/"
      normalized.empty? ? "/" : normalized
    end

    private def extract_tuple_case_candidates(line : String) : Array(Tuple(String, String))
      candidates = [] of Tuple(String, String)
      line.scan(/\bcase\s*\(\s*@?"([A-Za-z]+)"\s*,\s*@?"([^"]*)"\s*\)/) do |match|
        method = match[1].upcase
        path = match[2]
        next unless HTTP_METHODS.includes?(method)
        next unless looks_like_route_path?(path)

        candidates << {method, normalize_route_path(path)}
      end
      candidates.uniq
    end

    private def active_request_context(branch_stack : Array(BranchContext),
                                       switch_stack : Array(SwitchContext)) : Tuple(Array(String), Array(String))
      methods = [] of String
      paths = [] of String

      branch_stack.each do |ctx|
        methods.concat(ctx.methods)
        paths.concat(ctx.paths)
      end

      switch_stack.each do |ctx|
        methods.concat(ctx.methods)
        paths.concat(ctx.paths)
      end

      {methods.uniq, paths.uniq}
    end

    private def should_emit_from_line?(line_methods : Array(String),
                                       line_paths : Array(String),
                                       active_paths : Array(String)) : Bool
      return true unless line_paths.empty?
      !line_methods.empty? && !active_paths.empty?
    end

    private def switch_kind_for(line : String, method_vars : Array(String), path_vars : Array(String)) : String?
      match = line.match(/\bswitch\s*\((.*)\)/)
      return unless match

      selector = match[1]
      return "method" if method_signal?(selector, method_vars)
      "path" if path_signal?(selector, path_vars)
    end

    private def control_guard_line?(line : String) : Bool
      stripped = line.lstrip
      stripped.starts_with?("if") || stripped.starts_with?("else if")
    end

    private def block_depth(current_depth : Int32, depth_after : Int32) : Int32
      depth_after > current_depth ? depth_after : current_depth + 1
    end

    private def case_block_has_method_guard?(lines : Array(String),
                                             masked_lines : Array(String),
                                             start_index : Int32,
                                             method_vars : Array(String)) : Bool
      block, _ = extract_route_block(lines, masked_lines, start_index)
      method_signal?(block, method_vars)
    end

    private def emit_endpoint(file : String,
                              line_index : Int32,
                              raw_route : String,
                              raw_method : String,
                              lines : Array(String),
                              masked_lines : Array(String),
                              include_callee : Bool)
      method = raw_method.upcase
      return unless HTTP_METHODS.includes?(method)

      route = normalize_route_path(raw_route)
      block, block_start = extract_route_block(lines, masked_lines, line_index)

      endpoint = Endpoint.new(route, method, Details.new(PathInfo.new(file, line_index + 1)))
      extract_request_params(block, method).each { |param| endpoint.push_param(param) }
      attach_csharp_callees(endpoint, block, file, block_start + 1, include_callee)

      merge_endpoint(endpoint)
    end

    private def merge_endpoint(endpoint : Endpoint)
      existing = @result.find { |candidate| candidate.url == endpoint.url && candidate.method == endpoint.method }
      if existing
        endpoint.params.each { |param| existing.push_param(param) }
        endpoint.callees.each { |callee| existing.push_callee(callee) }
      else
        @result << endpoint
      end
    end

    private def extract_route_block(lines : Array(String),
                                    masked_lines : Array(String),
                                    start_index : Int32) : Tuple(String, Int32)
      start_masked = masked_lines[start_index]? || ""
      if start_masked.lstrip.starts_with?("case ")
        return extract_case_block(lines, masked_lines, start_index)
      end

      brace_index = start_index
      unless start_masked.includes?("{")
        probe = start_index + 1
        while probe < lines.size && probe <= start_index + 2
          probe_masked = masked_lines[probe]? || ""
          if probe_masked.strip.empty?
            probe += 1
            next
          end
          brace_index = probe if probe_masked.includes?("{")
          break
        end
      end

      if (masked_lines[brace_index]? || "").includes?("{")
        block = extract_method_block(lines, masked_lines, brace_index)
        if brace_index > start_index
          prefix = lines[start_index...brace_index].join("\n")
          block = prefix.empty? ? block : "#{prefix}\n#{block}"
        end
        return {block, start_index}
      end

      finish = start_index
      while finish + 1 < lines.size && finish < start_index + 4
        break if (masked_lines[finish]? || "").includes?(";") && finish > start_index
        finish += 1
      end
      {lines[start_index..finish].join("\n"), start_index}
    end

    private def extract_case_block(lines : Array(String),
                                   masked_lines : Array(String),
                                   start_index : Int32) : Tuple(String, Int32)
      indent = leading_spaces(masked_lines[start_index]? || "")
      io = String::Builder.new
      index = start_index

      while index < lines.size
        masked = masked_lines[index]? || ""
        break if index > start_index && closes_parent_case_scope?(masked, indent)
        break if index > start_index && sibling_case_line?(masked, indent)

        io << lines[index] << '\n'
        index += 1
      end

      {io.to_s, start_index}
    end

    private def closes_parent_case_scope?(masked : String, indent : Int32) : Bool
      stripped = masked.lstrip
      stripped.starts_with?("}") && leading_spaces(masked) < indent
    end

    private def sibling_case_line?(masked : String, indent : Int32) : Bool
      stripped = masked.lstrip
      return false unless stripped.starts_with?("case ") || stripped.starts_with?("default")
      leading_spaces(masked) <= indent
    end

    private def leading_spaces(line : String) : Int32
      line.size - line.lstrip.size
    end

    private def extract_request_params(block : String, method : String) : Array(Param)
      params = [] of Param
      query_vars = collection_aliases(block, "QueryString")
      header_vars = collection_aliases(block, "Headers")
      cookie_vars = collection_aliases(block, "Cookies")

      extract_indexer_params(block, query_vars, "query", params)
      extract_getter_params(block, query_vars, "query", params)
      extract_indexer_params(block, header_vars, "header", params)
      extract_getter_params(block, header_vars, "header", params)
      extract_indexer_params(block, cookie_vars, "cookie", params)

      if BODY_METHODS.includes?(method) && body_read?(block)
        params << Param.new("body", "", "json")
      end

      params.uniq { |param| "#{param.param_type}\0#{param.name}" }
    end

    private def collection_aliases(block : String, collection_name : String) : Array(String)
      aliases = [collection_name]
      block.each_line do |line|
        next unless line.includes?(collection_name)

        if match = line.match(/\b(?:var|NameValueCollection|CookieCollection)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*[^;]*\b#{collection_name}\b/)
          aliases << match[1] unless aliases.includes?(match[1])
        end
      end
      aliases
    end

    private def extract_indexer_params(block : String, vars : Array(String), param_type : String, params : Array(Param))
      vars.each do |var|
        escaped = Regex.escape(var)
        block.scan(/\b#{escaped}\s*\[\s*@?"([^"]+)"/) do |match|
          name = match[1].strip
          params << Param.new(name, "", param_type) unless name.empty?
        end
      end
    end

    private def extract_getter_params(block : String, vars : Array(String), param_type : String, params : Array(Param))
      vars.each do |var|
        escaped = Regex.escape(var)
        block.scan(/\b#{escaped}\s*\.\s*(?:Get|GetValues|GetFirst)\s*\(\s*@?"([^"]+)"/) do |match|
          name = match[1].strip
          params << Param.new(name, "", param_type) unless name.empty?
        end
      end
    end

    private def body_read?(block : String) : Bool
      block.includes?("InputStream") ||
        block.includes?("HasEntityBody") ||
        block.includes?("ReadToEnd") ||
        block.includes?("ReadToEndAsync")
    end
  end
end
