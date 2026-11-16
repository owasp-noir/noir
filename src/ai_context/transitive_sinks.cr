module NoirAIContext
  class Builder
    # ponytail: transitive callee sink walk stops at 3 hops below the handler
    # (handler -> f1 -> f2 -> f3); deeper call chains are not followed.
    MAX_TRANSITIVE_DEPTH  =  3
    MAX_HELPER_BODY_LINES = 80

    JS_TS_EXTS = %w[.ts .tsx .mts .cts .js .jsx .mjs .cjs]
    PY_EXTS    = %w[.py]
    GO_EXTS    = %w[.go]
    HASH_EXTS  = %w[.py .rb .cr .ex .exs .pl .pm]
    RUBY_EXTS  = %w[.rb .cr .ex .exs]

    CALL_EXPR_PATTERN = /(?<![\w$.])([A-Za-z_$][\w$]*(?:(?:\.|->|::)[A-Za-z_$][\w$]*)*)\s*\(/

    TRANSITIVE_SKIP_KEYWORDS = HELPER_BODY_KEYWORDS | Set{
      "else", "case", "except", "finally", "yield", "await", "async",
      "typeof", "sizeof", "delete", "throw", "raise", "assert",
      "select", "go", "defer", "make", "len", "cap", "append", "copy",
      "close", "panic", "recover", "range", "import", "require",
      "super", "constructor",
    }

    private record ResolvedCallTarget,
      call_name : String,
      path : String,
      line : Int32

    private record DefinitionSummary,
      sinks : Array(AIContextEntry),
      outgoing : Array(ResolvedCallTarget)

    private record TransitiveQueueItem,
      path : String,
      line : Int32,
      depth : Int32,
      chain : Array(String)

    # --- Python index records ---

    private record PyImportTarget,
      module_name : String,
      symbol : String?,
      relative_dots : Int32

    private class PyClassInfo
      property name : String
      property line : Int32
      property indent : Int32
      property methods = Hash(String, Array(Int32)).new
      property fields = Hash(String, String).new

      def initialize(@name, @line, @indent)
      end
    end

    private class PyFileIndex
      property imports = Hash(String, PyImportTarget).new
      property top_defs = Hash(String, Array(Int32)).new
      property classes = Hash(String, PyClassInfo).new
      property class_list = [] of PyClassInfo
    end

    # --- Go index records ---

    private record GoFieldType,
      file_path : String,
      import_alias : String?,
      type_name : String

    private record GoDefLoc,
      file_path : String,
      line : Int32,
      return_alias : String?,
      return_type : String?

    private class GoFileIndex
      property imports = Hash(String, String).new
    end

    private class GoPackageIndex
      property functions = Hash(String, Array(GoDefLoc)).new
      property methods = Hash(Tuple(String, String), Array(GoDefLoc)).new
      property structs = Hash(String, Hash(String, GoFieldType)).new
    end

    # --- JS/TS index records ---

    private record JsNamedImport,
      specifier : String,
      symbol : String

    private class JsClassInfo
      property name : String?
      property line : Int32
      property depth : Int32
      property methods = Hash(String, Array(Int32)).new
      property fields = Hash(String, String).new

      def initialize(@name, @line, @depth)
      end
    end

    private class JsFileIndex
      property default_imports = Hash(String, String).new
      property namespace_imports = Hash(String, String).new
      property named_imports = Hash(String, JsNamedImport).new
      property top_functions = Hash(String, Array(Int32)).new
      property exported_functions = Hash(String, Array(Int32)).new
      property export_aliases = Hash(String, String).new
      property default_export_name : String? = nil
      property default_export_line : Int32? = nil
      property classes = Hash(String, JsClassInfo).new
      property class_list = [] of JsClassInfo
      property default_export_class : JsClassInfo? = nil
    end

    @definition_summaries = {} of Tuple(String, Int32, Bool) => DefinitionSummary
    @py_files_by_norm : Hash(String, String)? = nil
    @py_indexes = {} of String => PyFileIndex
    @go_files_by_dir : Hash(String, Array(String))? = nil
    @go_modules : Array(Tuple(String, String))? = nil
    @go_file_indexes = {} of String => GoFileIndex
    @go_pkg_indexes = {} of String => GoPackageIndex
    @js_files_by_norm : Hash(String, String)? = nil
    @js_indexes = {} of String => JsFileIndex

    private def add_transitive_callee_sinks(context : AIContext, endpoint : Endpoint)
      return if endpoint.callees.empty?
      return if context.sinks.size >= AIContext::MAX_PER_SECTION

      visited = Set(Tuple(String, Int32)).new
      if (handler = endpoint.handler) && (h_path = handler.path) && (h_line = handler.line)
        visited << {h_path, h_line}
      end

      queue = Deque(TransitiveQueueItem).new
      endpoint.callees.each do |callee|
        next unless target = resolve_initial_callee(callee)
        next unless visited.add?(target)

        queue << TransitiveQueueItem.new(target[0], target[1], 1, [callee.name])
      end

      mobile = endpoint.mobile?
      while item = queue.shift?
        break if context.sinks.size >= AIContext::MAX_PER_SECTION

        summary = definition_summary(item.path, item.line, mobile)
        summary.sinks.each do |hit|
          break if context.sinks.size >= AIContext::MAX_PER_SECTION

          entry = with_transitive_chain(hit, item.chain, endpoint)
          context.push_sink(entry)
        end

        next if item.depth >= MAX_TRANSITIVE_DEPTH

        summary.outgoing.each do |next_call|
          target = {next_call.path, next_call.line}
          next unless visited.add?(target)

          queue << TransitiveQueueItem.new(
            next_call.path,
            next_call.line,
            item.depth + 1,
            item.chain + [next_call.call_name]
          )
        end
      end
    end

    private def with_transitive_chain(hit : AIContextEntry, chain : Array(String), endpoint : Endpoint) : AIContextEntry
      base_desc = hit.description || "Potential sink inferred from callee"
      desc = "#{base_desc} (reached via #{chain.join(" -> ")})"
      entry = AIContextEntry.new(
        hit.kind,
        hit.name,
        source: hit.source || "callee",
        description: desc,
        path: hit.path,
        line: hit.line,
        confidence: hit.confidence,
        snippet: hit.snippet
      )
      endpoint.mobile? ? normalize_mobile_sink(endpoint, entry) : entry
    end

    private def resolve_initial_callee(callee : Callee) : Tuple(String, Int32)?
      path = callee.path
      line = callee.line
      return unless path && line && line > 0

      lines = @reader.lines_for(path)
      return if lines.empty? || line > lines.size

      leaf = callee.name.split(/\.|->|::/).last
      if definition_at_line?(path, lines, line, leaf)
        return {path, line}
      end

      resolve_callee_target(callee.name, path, line, enclosing_def_line: nil)
    end

    private def definition_summary(path : String, def_line : Int32, mobile : Bool) : DefinitionSummary
      key = {path, def_line, mobile}
      if cached = @definition_summaries[key]?
        return cached
      end

      summary = build_definition_summary(path, def_line, mobile)
      @definition_summaries[key] = summary
      summary
    end

    NON_MOBILE_NAME_GATE   = Regex.union(NON_MOBILE_SINK_PATTERNS.flat_map(&.name_patterns))
    NON_MOBILE_SOURCE_GATE = Regex.union(NON_MOBILE_SINK_PATTERNS.flat_map(&.source_patterns))
    FILE_HANDLE_CALL_NAME  = /\A\w+\.(?:read|write)\w*\z/i
    SELECT_CALL_NAME       = /(?:\A|[.:>])select\z/i

    private def build_definition_summary(path : String, def_line : Int32, mobile : Bool) : DefinitionSummary
      sinks = [] of AIContextEntry
      outgoing = [] of ResolvedCallTarget
      seen_outgoing = Set(Tuple(String, String, Int32)).new
      sink_patterns = mobile ? SINK_PATTERNS : NON_MOBILE_SINK_PATTERNS
      repo_ext = REPOSITORY_SOURCE_EXTS.includes?(File.extname(path))

      body_lines = extract_helper_body_lines(path, def_line)
      body_lines.each do |line_num, code_line, call_scan_line|
        line_sunk_kinds = Set(String).new
        callee_snippet : String? = nil

        call_scan_line.scan(CALL_EXPR_PATTERN) do |match|
          called_name = match[1]
          leaf = called_name.split(/\.|->|::/).last
          next if TRANSITIVE_SKIP_KEYWORDS.includes?(called_name) || TRANSITIVE_SKIP_KEYWORDS.includes?(leaf)
          next if leaf.starts_with?("__")

          if target = resolve_callee_target(called_name, path, line_num, enclosing_def_line: def_line)
            next if target[0] == path && target[1] == def_line
            out_key = {called_name, target[0], target[1]}
            if seen_outgoing.add?(out_key)
              outgoing << ResolvedCallTarget.new(called_name, target[0], target[1])
            end
            next
          end

          next unless mobile || repo_ext || called_name.matches?(NON_MOBILE_NAME_GATE) ||
                      called_name.matches?(FILE_HANDLE_CALL_NAME) || called_name.matches?(SELECT_CALL_NAME)

          callee_snippet ||= @reader.snippet_for(path, line_num, CALLEE_SNIPPET_RADIUS)
          synthetic = Callee.new(called_name, path: path, line: line_num)
          if entry = body_callee_sink(synthetic, callee_snippet, sink_patterns)
            sinks << entry
            line_sunk_kinds << entry.kind
          end
        end

        next unless mobile || code_line.matches?(NON_MOBILE_SOURCE_GATE)

        sink_patterns.each do |pattern|
          next if line_sunk_kinds.includes?(pattern.kind)
          next unless pattern.source_patterns.any? { |rx| code_line.matches?(rx) }
          callee_snippet ||= @reader.snippet_for(path, line_num, CALLEE_SNIPPET_RADIUS)
          if entry = PatternMatcher.detect_body_line_pattern(pattern, code_line, callee_snippet, path, line_num)
            sinks << entry
            line_sunk_kinds << pattern.kind
          end
        end
      end

      DefinitionSummary.new(sinks, outgoing)
    end

    private def body_callee_sink(callee : Callee,
                                 callee_snippet : String?,
                                 sink_patterns : Array(PatternDefinition)) : AIContextEntry?
      if type = repository_call_type(callee.name, callee.path)
        return repository_sink(callee.name, type, callee.path, callee.line, callee_snippet)
      elsif handle_sink = file_handle_sink(callee, callee_snippet)
        return handle_sink
      elsif (raw_sink = PatternMatcher.detect_from_patterns(callee.name, callee_snippet, sink_patterns, callee.path, callee.line, "callee")) &&
            !in_memory_send_file?(raw_sink, callee) && !ktor_data_respond?(raw_sink, callee, callee_snippet)
        if BODY_JUDGED_SINK_KINDS.includes?(raw_sink.kind) && body_local_inert_helper?(raw_sink, callee, sink_patterns)
          return
        end
        return enrich_callee_sink(raw_sink, callee, callee_snippet)
      elsif select_sink = built_select_sink(callee, callee_snippet)
        return select_sink
      end
      nil
    end

    private def body_local_inert_helper?(sink : AIContextEntry, callee : Callee, patterns : Array(PatternDefinition)) : Bool
      return false unless pattern = patterns.find { |entry| entry.kind == sink.kind }
      return false unless (path = callee.path) && (line = callee.line)
      return false unless match = callee.name.match(/\A((?:self|this)\.|\$this->|@)?(\w+)\z/)

      name = match[2]
      return false if imported_names(path).includes?(name)

      lines = @reader.lines_for(path)
      self_call = !match[1]?.nil?
      return false unless def_line = definition_lines(path, name).find { |candidate| definition_in_scope?(path, lines, candidate, line, self_call) }

      !helper_reaches_kind?(path, def_line, name, pattern)
    end

    # --- Function body line extraction ---

    # Returns {1-based line_num, comment_stripped_code, comment_and_string_stripped_code}
    private def extract_helper_body_lines(path : String, def_line : Int32) : Array(Tuple(Int32, String, String))
      lines = @reader.lines_for(path)
      return [] of Tuple(Int32, String, String) if def_line < 1 || def_line > lines.size

      ext = File.extname(path).downcase
      if ext == ".py"
        extract_python_body_lines(lines, def_line)
      elsif RUBY_EXTS.includes?(ext)
        extract_end_body_lines(lines, def_line, ext)
      else
        extract_brace_body_lines(lines, def_line, ext)
      end
    end

    private def extract_python_body_lines(lines : Array(String), def_line : Int32) : Array(Tuple(Int32, String, String))
      result = [] of Tuple(Int32, String, String)
      start_idx = def_line - 1
      def_indent = lines[start_idx].size - lines[start_idx].lstrip.size
      in_sig = true
      paren_balance = 0

      limit = Math.min(start_idx + MAX_HELPER_BODY_LINES, lines.size - 1)
      start_idx.upto(limit) do |idx|
        raw = lines[idx]
        stripped = raw.strip
        code, scan = strip_line_comments_and_strings(raw, ".py", false)[0..1]

        if in_sig
          paren_balance += scan.count('(') - scan.count(')')
          if paren_balance <= 0 && (colon_idx = code.rindex(':'))
            in_sig = false
            tail_code = code[(colon_idx + 1)..].strip
            tail_scan = scan.size > colon_idx + 1 ? scan[(colon_idx + 1)..].strip : ""
            result << {idx + 1, tail_code, tail_scan} unless tail_code.empty?
          end
          next
        end

        next if stripped.empty? || code.strip.empty?
        indent = raw.size - raw.lstrip.size
        break if indent <= def_indent

        result << {idx + 1, code, scan}
      end
      result
    end

    private def extract_end_body_lines(lines : Array(String), def_line : Int32, ext : String) : Array(Tuple(Int32, String, String))
      result = [] of Tuple(Int32, String, String)
      start_idx = def_line - 1
      def_indent = lines[start_idx].size - lines[start_idx].lstrip.size
      limit = Math.min(start_idx + MAX_HELPER_BODY_LINES, lines.size - 1)

      (start_idx + 1).upto(limit) do |idx|
        raw = lines[idx]
        stripped = raw.strip
        next if stripped.empty?

        indent = raw.size - raw.lstrip.size
        break if indent <= def_indent && (stripped == "end" || !stripped.starts_with?("#"))
        code, scan, _ = strip_line_comments_and_strings(raw, ext, false)
        next if code.strip.empty?

        result << {idx + 1, code, scan}
      end
      result
    end

    private def extract_brace_body_lines(lines : Array(String), def_line : Int32, ext : String) : Array(Tuple(Int32, String, String))
      result = [] of Tuple(Int32, String, String)
      start_idx = def_line - 1
      limit = Math.min(start_idx + MAX_HELPER_BODY_LINES, lines.size - 1)
      in_block_comment = false
      opened_brace = false
      brace_depth = 0
      arrow_expr = false
      paren_balance = 0

      start_idx.upto(limit) do |idx|
        raw = lines[idx]
        code, scan, in_block_comment = strip_line_comments_and_strings(raw, ext, in_block_comment)

        if idx == start_idx
          paren_balance += scan.count('(') - scan.count(')')
          if open_pos = scan.index('{')
            opened_brace = true
            brace_depth += scan[open_pos..].count('{') - scan[open_pos..].count('}')
            tail_code = code[(open_pos + 1)..].strip
            tail_scan = scan[(open_pos + 1)..].strip
            if brace_depth <= 0
              # Single-line braced body like `function f() { return db.query(x); }`
              if close_pos = tail_code.rindex('}')
                tail_code = tail_code[0...close_pos].strip
                tail_scan = tail_scan[0...Math.min(close_pos, tail_scan.size)].strip
              end
              result << {idx + 1, tail_code, tail_scan} unless tail_code.empty?
              break
            end
            result << {idx + 1, tail_code, tail_scan} unless tail_code.empty?
          elsif JS_TS_EXTS.includes?(ext) && paren_balance <= 0 && (arrow_pos = scan.index("=>"))
            after_code = code[(arrow_pos + 2)..].strip
            after_scan = scan[(arrow_pos + 2)..].strip
            arrow_expr = true unless after_scan.starts_with?('{')
            if !after_code.empty?
              result << {idx + 1, after_code, after_scan}
              paren_balance += after_scan.count('(') - after_scan.count(')')
              break if arrow_expr && paren_balance <= 0 && (after_scan.ends_with?(";") || !after_scan.matches?(/[+\-*\/&|?:,(]\z/))
            end
          end
          next
        end

        if arrow_expr
          break if code.strip.empty?
          result << {idx + 1, code, scan}
          paren_balance += scan.count('(') - scan.count(')')
          break if paren_balance <= 0 && (scan.strip.ends_with?(";") || !scan.strip.matches?(/[+\-*\/&|?:,(]\z/))
          next
        end

        if !opened_brace
          paren_balance += scan.count('(') - scan.count(')')
          if open_pos = scan.index('{')
            opened_brace = true
            brace_depth += scan[open_pos..].count('{') - scan[open_pos..].count('}')
            tail_code = code[(open_pos + 1)..].strip
            tail_scan = scan[(open_pos + 1)..].strip
            if brace_depth <= 0
              if close_pos = tail_code.rindex('}')
                tail_code = tail_code[0...close_pos].strip
                tail_scan = tail_scan[0...Math.min(close_pos, tail_scan.size)].strip
              end
              result << {idx + 1, tail_code, tail_scan} unless tail_code.empty?
              break
            end
            result << {idx + 1, tail_code, tail_scan} unless tail_code.empty?
          elsif JS_TS_EXTS.includes?(ext) && paren_balance <= 0 && (arrow_pos = scan.index("=>"))
            after_code = code[(arrow_pos + 2)..].strip
            after_scan = scan[(arrow_pos + 2)..].strip
            arrow_expr = true
            result << {idx + 1, after_code, after_scan} unless after_code.empty?
          end
          next
        end

        opens = scan.count('{')
        closes = scan.count('}')
        next_depth = brace_depth + opens - closes
        if next_depth <= 0
          if close_pos = scan.rindex('}')
            before_code = code[0...Math.min(close_pos, code.size)].strip
            before_scan = scan[0...close_pos].strip
            result << {idx + 1, before_code, before_scan} unless before_code.empty?
          end
          break
        end
        brace_depth = next_depth
        result << {idx + 1, code, scan} unless code.strip.empty?
      end

      result
    end

    # Strips comments (producing `code`) and also blanks string contents
    # (producing `scan`) in a single pass while tracking block comments.
    private def strip_line_comments_and_strings(raw : String, ext : String, in_block_comment : Bool) : Tuple(String, String, Bool)
      hash_comments = HASH_EXTS.includes?(ext)
      c_comments = !hash_comments
      code = String::Builder.new(raw.bytesize)
      scan = String::Builder.new(raw.bytesize)

      i = 0
      n = raw.size
      quote : Char? = nil
      escaped = false

      while i < n
        ch = raw[i]

        if in_block_comment
          if ch == '*' && i + 1 < n && raw[i + 1] == '/'
            in_block_comment = false
            code << "  "
            scan << "  "
            i += 2
          else
            code << ' '
            scan << ' '
            i += 1
          end
          next
        end

        if q = quote
          code << ch
          scan << ' '
          if escaped
            escaped = false
          elsif ch == '\\' && q != '`'
            escaped = true
          elsif ch == q
            quote = nil
          end
          i += 1
          next
        end

        if hash_comments && ch == '#'
          break
        elsif c_comments && ch == '/' && i + 1 < n
          nxt = raw[i + 1]
          if nxt == '/'
            break
          elsif nxt == '*'
            in_block_comment = true
            code << "  "
            scan << "  "
            i += 2
            next
          end
        end

        if ch == '\'' || ch == '"' || (ch == '`' && (ext == ".go" || JS_TS_EXTS.includes?(ext)))
          quote = ch
          code << ch
          scan << ch
          i += 1
          next
        end

        code << ch
        scan << ch
        i += 1
      end

      {code.to_s, scan.to_s, in_block_comment}
    end

    # --- Definition header check ---

    private def definition_at_line?(path : String, lines : Array(String), line : Int32, name : String) : Bool
      return false if name.empty? || line < 1 || line > lines.size

      text = lines[line - 1].lstrip
      esc = Regex.escape(name)
      ext = File.extname(path).downcase

      if ext == ".py"
        text.matches?(/\A(?:async\s+)?def\s+#{esc}\s*\(/)
      elsif ext == ".go"
        text.matches?(/\Afunc\s+(?:\([^)]*\)\s*)?(?:\[[^\]]*\]\s*)?#{esc}\s*[\[(]/)
      elsif JS_TS_EXTS.includes?(ext)
        text.matches?(/\A(?:export\s+(?:default\s+)?)?(?:async\s+)?function\s*\*?\s*#{esc}\s*(?:<[^>]*>)?\s*\(/) ||
          text.matches?(/\A(?:(?:export\s+)?(?:const|let|var)\s+)?#{esc}\s*(?::[^=]+)?=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::[^=]+)?=>|[A-Za-z_$][\w$]*\s*=>)/) ||
          text.matches?(/\A(?:(?:public|private|protected|static|async|override|readonly|get|set)\s+)*#{esc}\s*(?:<[^>]*>)?\s*\([^)]*\)\s*(?::\s*[^{=]+)?\s*\{/) ||
          text.matches?(/\A(?:module\.)?exports\.#{esc}\s*=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)/)
      else
        text.matches?(/\A(?:(?:public|private|protected|internal|static|final|abstract|override|suspend|inline|async|unsafe|extern|pub(?:\([^)]*\))?)\s+)*(?:def|defp|fun|function|func|fn|sub)\s+(?:\([^)]*\)\s*)?(?:self\.)?#{esc}\b/) ||
          text.matches?(/\A(?:(?:public|private|protected|internal|static|final|abstract|override|virtual|async|suspend)\s+)+(?:[\w<>\[\],.?]+\s+)+#{esc}\s*\(/)
      end
    end

    # --- Language-dispatched resolution ---

    private def resolve_callee_target(name : String,
                                      caller_path : String,
                                      caller_line : Int32,
                                      enclosing_def_line : Int32?) : Tuple(String, Int32)?
      ext = File.extname(caller_path).downcase
      if ext == ".py"
        resolve_python_callee(name, caller_path, caller_line, enclosing_def_line)
      elsif ext == ".go"
        resolve_go_callee(name, caller_path, caller_line, enclosing_def_line)
      elsif JS_TS_EXTS.includes?(ext)
        resolve_js_callee(name, caller_path, caller_line, enclosing_def_line)
      else
        resolve_same_file_fallback(name, caller_path, caller_line)
      end
    end

    private def resolve_same_file_fallback(name : String, caller_path : String, caller_line : Int32) : Tuple(String, Int32)?
      return unless match = name.match(/\A((?:self|this)\.|\$this->)?([A-Za-z_]\w*)\z/)

      bare = match[2]
      self_call = !match[1]?.nil?
      return if !self_call && imported_names(caller_path).includes?(bare)

      lines = @reader.lines_for(caller_path)
      candidates = definition_lines(caller_path, bare).select do |candidate|
        definition_at_line?(caller_path, lines, candidate, bare) &&
          definition_in_scope?(caller_path, lines, candidate, caller_line, self_call)
      end
      return unless candidates.size == 1

      {caller_path, candidates[0]}
    end

    # =========================================================================
    # Python resolution
    # =========================================================================

    private def py_files_map : Hash(String, String)
      if cached = @py_files_by_norm
        return cached
      end

      map = {} of String => String
      CodeLocator.instance.files_by_extension(".py").each do |path|
        map[Path.new(path).normalize.to_s] = path
      end
      @py_files_by_norm = map
    end

    private def py_file_index(path : String) : PyFileIndex
      if cached = @py_indexes[path]?
        return cached
      end

      idx = PyFileIndex.new
      lines = @reader.lines_for(path)
      open_from : Tuple(Int32, String, String)? = nil # {dots, module, buf}
      open_classes = [] of PyClassInfo
      open_methods = [] of Tuple(Int32, PyClassInfo, Hash(String, String)) # {method_indent, class, param_types}

      lines.each_with_index do |raw, i|
        line_num = i + 1
        stripped = raw.lstrip
        next if stripped.empty? || stripped.starts_with?('#')
        indent = raw.size - stripped.size

        if from_state = open_from
          dots, mod, buf = from_state
          combined = buf + " " + stripped
          if combined.includes?(')')
            parse_py_from_import_items(idx, dots, mod, combined)
            open_from = nil
          else
            open_from = {dots, mod, combined}
          end
          next
        end

        while (last_m = open_methods.last?) && indent <= last_m[0]
          open_methods.pop
        end
        while (last_c = open_classes.last?) && indent <= last_c.indent
          open_classes.pop
        end

        if indent == 0
          if m = stripped.match(/\Afrom\s+(\.*)([\w.]*)\s+import\s+(.+)/)
            dots = m[1].size
            mod = m[2]
            rest = m[3]
            if rest.includes?('(') && !rest.includes?(')')
              open_from = {dots, mod, rest}
            else
              parse_py_from_import_items(idx, dots, mod, rest)
            end
            next
          elsif m = stripped.match(/\Aimport\s+(.+)/)
            parse_py_import_items(idx, m[1])
            next
          end
        end

        if m = stripped.match(/\Aclass\s+([A-Za-z_]\w*)\b/)
          cls = PyClassInfo.new(m[1], line_num, indent)
          idx.classes[cls.name] = cls unless idx.classes.has_key?(cls.name)
          idx.class_list << cls
          open_classes << cls
          next
        end

        if m = stripped.match(/\A(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\((.*)/)
          fn_name = m[1]
          if cls = open_classes.last?
            # Direct method of enclosing class (not a nested def inside a method)
            if open_methods.empty? || indent <= open_methods.last[0]
              (cls.methods[fn_name] ||= [] of Int32) << line_num
              param_types = parse_py_param_types(m[2])
              open_methods << {indent, cls, param_types}
            end
          elsif indent == 0
            (idx.top_defs[fn_name] ||= [] of Int32) << line_num
          end
          next
        end

        if cls = open_classes.last?
          if cur_method = open_methods.last?
            _, m_cls, param_types = cur_method
            if m_cls.same?(cls)
              if m = stripped.match(/\Aself\.([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*)\b/)
                cls.fields[m[1]] ||= m[2]
              elsif m = stripped.match(/\Aself\.([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*\(/)
                cls.fields[m[1]] ||= m[2]
              elsif m = stripped.match(/\Aself\.([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*(?:#.*)?\z/)
                if ptype = param_types[m[2]]?
                  cls.fields[m[1]] ||= ptype
                end
              end
            end
          elsif m = stripped.match(/\A([A-Za-z_]\w*)\s*:\s*([A-Za-z_]\w*)\b/)
            cls.fields[m[1]] ||= m[2]
          end
        end
      end

      @py_indexes[path] = idx
    end

    private def parse_py_param_types(rest : String) : Hash(String, String)
      types = {} of String => String
      head = rest.split("):", 2)[0]
      head.split(',').each do |part|
        if m = part.strip.match(/\A([A-Za-z_]\w*)\s*:\s*([A-Za-z_][\w.]*)/)
          types[m[1]] = m[2].split('.').last
        end
      end
      types
    end

    private def parse_py_from_import_items(idx : PyFileIndex, dots : Int32, mod : String, rest : String)
      cleaned = rest.split('#', 2)[0].tr("()", " ")
      cleaned.split(',').each do |item|
        entry = item.strip
        next if entry.empty? || entry == "*"
        if m = entry.match(/\A([A-Za-z_]\w*)\s+as\s+([A-Za-z_]\w*)\z/)
          idx.imports[m[2]] = PyImportTarget.new(mod, m[1], dots)
        elsif entry.matches?(/\A[A-Za-z_]\w*\z/)
          idx.imports[entry] = PyImportTarget.new(mod, entry, dots)
        end
      end
    end

    private def parse_py_import_items(idx : PyFileIndex, rest : String)
      cleaned = rest.split('#', 2)[0]
      cleaned.split(',').each do |item|
        entry = item.strip
        next if entry.empty?
        if m = entry.match(/\A([A-Za-z_][\w.]*)\s+as\s+([A-Za-z_]\w*)\z/)
          idx.imports[m[2]] = PyImportTarget.new(m[1], nil, 0)
        elsif entry.matches?(/\A[A-Za-z_][\w.]*\z/)
          idx.imports[entry] = PyImportTarget.new(entry, nil, 0)
        end
      end
    end

    private def resolve_python_module(caller_path : String, module_name : String, relative_dots : Int32) : String?
      files = py_files_map
      return if files.empty?

      if relative_dots > 0
        dir = Path.new(caller_path).normalize.dirname
        (relative_dots - 1).times { dir = File.dirname(dir) }
        subpath = module_name.tr(".", "/")
        candidates = if subpath.empty?
                       [Path.new(dir, "__init__.py").normalize.to_s]
                     else
                       [
                         Path.new(dir, "#{subpath}.py").normalize.to_s,
                         Path.new(dir, subpath, "__init__.py").normalize.to_s,
                       ]
                     end
        matches = candidates.compact_map { |cand| files[cand]? }.uniq!
        return matches.size == 1 ? matches[0] : nil
      end

      return if module_name.empty?
      subpath = module_name.tr(".", "/")
      suffix_py = "/#{subpath}.py"
      suffix_init = "/#{subpath}/__init__.py"
      exact_py = "#{subpath}.py"
      exact_init = "#{subpath}/__init__.py"

      matches = [] of String
      files.each do |norm, orig|
        if norm == exact_py || norm == exact_init || norm.ends_with?(suffix_py) || norm.ends_with?(suffix_init)
          matches << orig
        end
      end
      matches.size == 1 ? matches[0] : nil
    end

    private def resolve_python_callee(name : String,
                                      caller_path : String,
                                      caller_line : Int32,
                                      enclosing_def_line : Int32?) : Tuple(String, Int32)?
      parts = name.split('.')
      return if parts.empty?

      idx = py_file_index(caller_path)
      case parts.size
      when 1
        fn = parts[0]
        if imp = idx.imports[fn]?
          return unless target_path = resolve_python_module(caller_path, imp.module_name, imp.relative_dots)
          sym = imp.symbol || fn
          lines = py_file_index(target_path).top_defs[sym]?
          return lines && lines.size == 1 ? {target_path, lines[0]} : nil
        end
        lines = idx.top_defs[fn]?
        lines && lines.size == 1 ? {caller_path, lines[0]} : nil
      when 2
        recv, meth = parts[0], parts[1]
        if recv == "self" || recv == "cls"
          return unless cls = enclosing_py_class(idx, caller_path, caller_line)
          lines = cls.methods[meth]?
          return lines && lines.size == 1 ? {caller_path, lines[0]} : nil
        end

        if imp = idx.imports[recv]?
          return resolve_python_imported_member(caller_path, imp, meth)
        end

        if cls = idx.classes[recv]?
          lines = cls.methods[meth]?
          return lines && lines.size == 1 ? {caller_path, lines[0]} : nil
        end

        if type_name = python_local_var_type(caller_path, caller_line, enclosing_def_line, recv)
          return resolve_python_class_method(caller_path, idx, type_name, meth)
        end
        nil
      when 3
        if parts[0] == "self"
          return unless cls = enclosing_py_class(idx, caller_path, caller_line)
          return unless type_name = cls.fields[parts[1]]?
          return resolve_python_class_method(caller_path, idx, type_name, parts[2])
        end
        prefix = parts[0..-2].join('.')
        if imp = idx.imports[prefix]?
          return unless target_path = resolve_python_module(caller_path, imp.module_name, imp.relative_dots)
          lines = py_file_index(target_path).top_defs[parts[2]]?
          return lines && lines.size == 1 ? {target_path, lines[0]} : nil
        end
        nil
      else
        prefix = parts[0..-2].join('.')
        if imp = idx.imports[prefix]?
          return unless target_path = resolve_python_module(caller_path, imp.module_name, imp.relative_dots)
          lines = py_file_index(target_path).top_defs[parts.last]?
          return lines && lines.size == 1 ? {target_path, lines[0]} : nil
        end
        nil
      end
    end

    private def resolve_python_imported_member(caller_path : String, imp : PyImportTarget, member : String) : Tuple(String, Int32)?
      if sym = imp.symbol
        submod = imp.module_name.empty? ? sym : "#{imp.module_name}.#{sym}"
        if sub_path = resolve_python_module(caller_path, submod, imp.relative_dots)
          lines = py_file_index(sub_path).top_defs[member]?
          return {sub_path, lines[0]} if lines && lines.size == 1
        end
        if mod_path = resolve_python_module(caller_path, imp.module_name, imp.relative_dots)
          if cls = py_file_index(mod_path).classes[sym]?
            lines = cls.methods[member]?
            return {mod_path, lines[0]} if lines && lines.size == 1
          end
        end
        nil
      else
        return unless mod_path = resolve_python_module(caller_path, imp.module_name, imp.relative_dots)
        lines = py_file_index(mod_path).top_defs[member]?
        lines && lines.size == 1 ? {mod_path, lines[0]} : nil
      end
    end

    private def resolve_python_class_method(caller_path : String,
                                            caller_idx : PyFileIndex,
                                            type_name : String,
                                            method_name : String) : Tuple(String, Int32)?
      if cls = caller_idx.classes[type_name]?
        lines = cls.methods[method_name]?
        return lines && lines.size == 1 ? {caller_path, lines[0]} : nil
      end

      if imp = caller_idx.imports[type_name]?
        return unless mod_path = resolve_python_module(caller_path, imp.module_name, imp.relative_dots)
        sym = imp.symbol || type_name
        if cls = py_file_index(mod_path).classes[sym]?
          lines = cls.methods[method_name]?
          return lines && lines.size == 1 ? {mod_path, lines[0]} : nil
        end
      end
      nil
    end

    private def enclosing_py_class(idx : PyFileIndex, path : String, line : Int32) : PyClassInfo?
      lines = @reader.lines_for(path)
      return if line < 1 || line > lines.size
      line_indent = lines[line - 1].size - lines[line - 1].lstrip.size

      best : PyClassInfo? = nil
      idx.class_list.each do |cls|
        break if cls.line >= line
        if line_indent > cls.indent
          best = cls
        elsif best && cls.indent <= best.indent
          best = nil
        end
      end
      best
    end

    private def python_local_var_type(path : String, line : Int32, enclosing_def_line : Int32?, var_name : String) : String?
      lines = @reader.lines_for(path)
      return if line < 1 || line > lines.size

      start_line = enclosing_def_line || 1
      esc = Regex.escape(var_name)
      min_indent = lines[line - 1].size - lines[line - 1].lstrip.size

      (line - 2).downto(Math.max(start_line - 1, 0)) do |i|
        raw = lines[i]
        stripped = raw.lstrip
        next if stripped.empty? || stripped.starts_with?('#')
        indent = raw.size - stripped.size
        next if indent > min_indent && !stripped.starts_with?("def ") && !stripped.starts_with?("async def ")
        min_indent = Math.min(min_indent, indent)

        if m = stripped.match(/\A#{esc}\s*:\s*([A-Za-z_]\w*)\b/)
          return m[1]
        elsif m = stripped.match(/\A#{esc}\s*=\s*([A-Za-z_]\w*)\s*\(/)
          return m[1]
        elsif stripped.matches?(/\A(?:async\s+)?def\s+/)
          if m = stripped.match(/\b#{esc}\s*:\s*([A-Za-z_]\w*)\b/)
            return m[1]
          end
          break unless enclosing_def_line.nil?
        end
      end
      nil
    end

    # =========================================================================
    # Go resolution
    # =========================================================================

    private def go_files_by_dir : Hash(String, Array(String))
      if cached = @go_files_by_dir
        return cached
      end

      grouped = {} of String => Array(String)
      CodeLocator.instance.files_by_extension(".go").each do |path|
        next if path.ends_with?("_test.go")
        dir = Path.new(path).normalize.dirname
        (grouped[dir] ||= [] of String) << path
      end
      @go_files_by_dir = grouped
    end

    private def go_modules : Array(Tuple(String, String))
      if cached = @go_modules
        return cached
      end

      mods = [] of Tuple(String, String)
      CodeLocator.instance.files_by_basename("go.mod").each do |path|
        root_dir = Path.new(path).normalize.dirname
        @reader.lines_for(path).each do |line|
          if m = line.match(/\A\s*module\s+(\S+)/)
            mods << {root_dir, m[1]}
            break
          end
        end
      end
      # Longest module root first so nested modules win
      mods.sort_by! { |root, _| -root.size }
      @go_modules = mods
    end

    private def go_file_index(path : String) : GoFileIndex
      if cached = @go_file_indexes[path]?
        return cached
      end

      idx = GoFileIndex.new
      in_import_block = false
      @reader.lines_for(path).each do |raw|
        line = raw.split("//", 2)[0].strip
        next if line.empty?

        if in_import_block
          if line.starts_with?(')')
            in_import_block = false
            next
          end
          parse_go_import_spec(idx, line)
          next
        end

        if line.matches?(/\Aimport\s*\(/)
          if line.includes?(')')
            inner = line.sub(/\Aimport\s*\(/, "").sub(/\).*\z/, "")
            parse_go_import_spec(idx, inner)
          else
            in_import_block = true
          end
        elsif line.starts_with?("import ")
          parse_go_import_spec(idx, line.sub(/\Aimport\s+/, ""))
        elsif line.starts_with?("func ") || line.starts_with?("type ") || line.starts_with?("var ") || line.starts_with?("const ")
          break
        end
      end

      @go_file_indexes[path] = idx
    end

    private def parse_go_import_spec(idx : GoFileIndex, spec : String)
      return unless m = spec.strip.match(/\A(?:([A-Za-z_.]\w*|\.)\s+)?["`]([^"`]+)["`]/)

      alias_name = m[1]?
      import_path = m[2]
      return if alias_name == "_" || alias_name == "."

      name = alias_name || go_default_import_alias(import_path)
      idx.imports[name] = import_path unless name.empty?
    end

    private def go_default_import_alias(import_path : String) : String
      parts = import_path.split('/')
      return "" if parts.empty?
      last = parts.last
      last.matches?(/\Av\d+\z/) && parts.size > 1 ? parts[-2] : last
    end

    private def resolve_go_import_dir(caller_path : String, import_path : String) : String?
      dirs = go_files_by_dir
      return if dirs.empty?

      norm_caller = Path.new(caller_path).normalize.to_s
      go_modules.each do |root_dir, mod_path|
        if import_path == mod_path
          return root_dir if dirs.has_key?(root_dir)
        elsif import_path.starts_with?("#{mod_path}/")
          rel = import_path[(mod_path.size + 1)..]
          cand = Path.new(root_dir, rel).normalize.to_s
          if dirs.has_key?(cand)
            return cand if root_dir == "." || norm_caller.starts_with?("#{root_dir}/") || norm_caller == root_dir
          end
        end
      end

      # Fallback if no go.mod matched (e.g., fixture without go.mod)
      if go_modules.empty?
        suffix = "/#{import_path}"
        matches = dirs.keys.select { |dir| dir == import_path || dir.ends_with?(suffix) }
        return matches[0] if matches.size == 1
      end
      nil
    end

    private def go_package_index(pkg_dir : String) : GoPackageIndex
      if cached = @go_pkg_indexes[pkg_dir]?
        return cached
      end

      pkg = GoPackageIndex.new
      files = go_files_by_dir[pkg_dir]? || [] of String
      files.each do |file_path|
        lines = @reader.lines_for(file_path)
        in_struct : Hash(String, GoFieldType)? = nil

        lines.each_with_index do |raw, i|
          line_num = i + 1
          code = raw.split("//", 2)[0].strip
          next if code.empty?

          if fields = in_struct
            if code.starts_with?('}')
              in_struct = nil
              next
            end
            # Strip trailing struct tag
            field_part = code.split('`', 2)[0].strip
            if m = field_part.match(/\A([A-Za-z_]\w*)\s+\*?(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\b/)
              fields[m[1]] = GoFieldType.new(file_path, m[2]?, m[3])
            end
            next
          end

          if m = code.match(/\Atype\s+([A-Za-z_]\w*)\s+struct\s*\{/)
            unless code.includes?('}')
              in_struct = (pkg.structs[m[1]] ||= {} of String => GoFieldType)
            end
          elsif m = code.match(/\Afunc\s*\(\s*(?:\w+\s+)?\*?([A-Za-z_]\w*)(?:\[[^\]]*\])?\s*\)\s*([A-Za-z_]\w*)\s*[\[(](.*)/)
            ret_alias, ret_type = parse_go_return_type(m[3])
            (pkg.methods[{m[1], m[2]}] ||= [] of GoDefLoc) << GoDefLoc.new(file_path, line_num, ret_alias, ret_type)
          elsif m = code.match(/\Afunc\s+([A-Za-z_]\w*)\s*[\[(](.*)/)
            ret_alias, ret_type = parse_go_return_type(m[2])
            (pkg.functions[m[1]] ||= [] of GoDefLoc) << GoDefLoc.new(file_path, line_num, ret_alias, ret_type)
          end
        end
      end

      @go_pkg_indexes[pkg_dir] = pkg
    end

    private def parse_go_return_type(after_open_paren : String) : Tuple(String?, String?)
      # Extract return clause between last `)` of params and `{`
      sig = after_open_paren.split('{', 2)[0]
      close_idx = sig.rindex(')')
      return {nil, nil} unless close_idx

      ret = sig[(close_idx + 1)..].strip
      return {nil, nil} if ret.empty?

      if m = ret.match(/\A\(?\s*\*?(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\b/)
        {m[1]?, m[2]}
      else
        {nil, nil}
      end
    end

    private def resolve_go_callee(name : String,
                                  caller_path : String,
                                  caller_line : Int32,
                                  enclosing_def_line : Int32?) : Tuple(String, Int32)?
      parts = name.split('.')
      return if parts.empty?

      caller_dir = Path.new(caller_path).normalize.dirname
      caller_pkg = go_package_index(caller_dir)
      file_idx = go_file_index(caller_path)

      if parts.size == 1
        defs = caller_pkg.functions[parts[0]]?
        return defs && defs.size == 1 ? {defs[0].file_path, defs[0].line} : nil
      end

      head = parts[0]
      if parts.size == 2
        # Package-qualified function call: `pkg.Func(...)`
        if import_path = file_idx.imports[head]?
          return unless target_dir = resolve_go_import_dir(caller_path, import_path)
          defs = go_package_index(target_dir).functions[parts[1]]?
          return defs && defs.size == 1 ? {defs[0].file_path, defs[0].line} : nil
        end
      end

      # Receiver / local / parameter variable chain: `h.svc.Search` or `h.helper`
      current_type = resolve_go_var_type(caller_path, caller_dir, caller_line, enclosing_def_line, head, file_idx)
      return unless current_type

      cur_dir, cur_struct = current_type
      1.upto(parts.size - 2) do |i|
        field_name = parts[i]
        pkg = go_package_index(cur_dir)
        struct_fields = pkg.structs[cur_struct]?
        return unless struct_fields
        return unless field = struct_fields[field_name]?

        if alias_name = field.import_alias
          field_imports = go_file_index(field.file_path).imports
          return unless import_path = field_imports[alias_name]?
          return unless next_dir = resolve_go_import_dir(field.file_path, import_path)
          cur_dir = next_dir
        end
        cur_struct = field.type_name
      end

      meth_name = parts.last
      defs = go_package_index(cur_dir).methods[{cur_struct, meth_name}]?
      defs && defs.size == 1 ? {defs[0].file_path, defs[0].line} : nil
    end

    private def resolve_go_var_type(caller_path : String,
                                    caller_dir : String,
                                    caller_line : Int32,
                                    enclosing_def_line : Int32?,
                                    var_name : String,
                                    file_idx : GoFileIndex) : Tuple(String, String)?
      lines = @reader.lines_for(caller_path)
      return if caller_line < 1 || caller_line > lines.size

      esc = Regex.escape(var_name)
      stop_line = enclosing_def_line || 1
      # Walk backward tracking enclosing brace depth
      depth = 0
      depths = Array(Int32).new(caller_line, 0)
      0.upto(caller_line - 1) do |i|
        depths[i] = depth
        _, scan, _ = strip_line_comments_and_strings(lines[i], ".go", false)
        depth += scan.count('{') - scan.count('}')
      end
      min_depth = depths[caller_line - 1]

      (caller_line - 1).downto(Math.max(stop_line - 1, 0)) do |i|
        next if depths[i] > min_depth
        min_depth = depths[i]

        code = lines[i].split("//", 2)[0].strip
        next if code.empty?

        # Function/method signature receiver + parameters
        if m = code.match(/\Afunc\s*(?:\(\s*([A-Za-z_]\w*)\s+\*?([A-Za-z_]\w*)(?:\[[^\]]*\])?\s*\)\s*)?[A-Za-z_]\w*\s*(?:\[[^\]]*\])?\s*\(([^)]*)/)
          if m[1]? == var_name && (rtype = m[2]?)
            return {caller_dir, rtype}
          end
          if type = go_param_type_in_list(m[3], var_name, caller_path, caller_dir, file_idx)
            return type
          end
          break
        elsif m = code.match(/\Afunc\s*\(([^)]*)\)/)
          if type = go_param_type_in_list(m[1], var_name, caller_path, caller_dir, file_idx)
            return type
          end
        end

        next if i == caller_line - 1

        # `var svc *pkg.Type` or `svc := &pkg.Type{...}` or `svc := pkg.NewType(...)`
        if m = code.match(/\Avar\s+#{esc}\s+\*?(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\b/)
          return resolve_go_type_ref(caller_path, caller_dir, file_idx, m[1]?, m[2])
        elsif m = code.match(/\A#{esc}\s*(?:,\s*\w+\s*)?:=\s*&?(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\s*\{/)
          return resolve_go_type_ref(caller_path, caller_dir, file_idx, m[1]?, m[2])
        elsif m = code.match(/\A#{esc}\s*(?:,\s*\w+\s*)?:=\s*(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\s*\(/)
          if alias_name = m[1]?
            if import_path = file_idx.imports[alias_name]?
              if target_dir = resolve_go_import_dir(caller_path, import_path)
                defs = go_package_index(target_dir).functions[m[2]]?
                if defs && defs.size == 1 && (rt = defs[0].return_type)
                  return resolve_go_type_ref(defs[0].file_path, target_dir, go_file_index(defs[0].file_path), defs[0].return_alias, rt)
                end
              end
            end
          else
            defs = go_package_index(caller_dir).functions[m[2]]?
            if defs && defs.size == 1 && (rt = defs[0].return_type)
              return resolve_go_type_ref(defs[0].file_path, caller_dir, go_file_index(defs[0].file_path), defs[0].return_alias, rt)
            end
          end
        end
      end
      nil
    end

    private def go_param_type_in_list(param_list : String,
                                      var_name : String,
                                      caller_path : String,
                                      caller_dir : String,
                                      file_idx : GoFileIndex) : Tuple(String, String)?
      esc = Regex.escape(var_name)
      param_list.split(',').each do |part|
        if m = part.strip.match(/\b#{esc}\s+\*?(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)\b/)
          return resolve_go_type_ref(caller_path, caller_dir, file_idx, m[1]?, m[2])
        end
      end
      nil
    end

    private def resolve_go_type_ref(file_path : String,
                                    pkg_dir : String,
                                    file_idx : GoFileIndex,
                                    alias_name : String?,
                                    type_name : String) : Tuple(String, String)?
      if alias_name
        return unless import_path = file_idx.imports[alias_name]?
        return unless target_dir = resolve_go_import_dir(file_path, import_path)
        {target_dir, type_name}
      else
        {pkg_dir, type_name}
      end
    end

    # =========================================================================
    # JS / TS resolution
    # =========================================================================

    private def js_files_map : Hash(String, String)
      if cached = @js_files_by_norm
        return cached
      end

      map = {} of String => String
      JS_TS_EXTS.each do |ext|
        CodeLocator.instance.files_by_extension(ext).each do |path|
          map[Path.new(path).normalize.to_s] = path
        end
      end
      @js_files_by_norm = map
    end

    private def js_file_index(path : String) : JsFileIndex
      if cached = @js_indexes[path]?
        return cached
      end

      idx = JsFileIndex.new
      lines = @reader.lines_for(path)
      ext = File.extname(path).downcase

      in_block_comment = false
      brace_depth = 0
      open_import_buf : String? = nil
      open_cjs_export_buf : String? = nil
      open_esm_export_buf : String? = nil
      open_class : JsClassInfo? = nil
      in_constructor = false
      ctor_params = {} of String => String

      lines.each_with_index do |raw, i|
        line_num = i + 1
        code, scan, in_block_comment = strip_line_comments_and_strings(raw, ext, in_block_comment)
        trimmed = code.strip

        # Multi-line import `{ ... } from '...'`
        if buf = open_import_buf
          combined = buf + " " + trimmed
          if combined.matches?(/\bfrom\s+['"][^'"]+['"]/)
            parse_js_import_statement(idx, combined)
            open_import_buf = nil
          else
            open_import_buf = combined
          end
          brace_depth += scan.count('{') - scan.count('}')
          next
        end

        # Multi-line `module.exports = { ... }`
        if buf = open_cjs_export_buf
          combined = buf + "\n" + trimmed
          if trimmed.includes?('}')
            parse_cjs_exports_block(idx, combined, line_num)
            open_cjs_export_buf = nil
          else
            if m = trimmed.match(/\A(?:async\s+)?([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{/)
              (idx.exported_functions[m[1]] ||= [] of Int32) << line_num
            elsif m = trimmed.match(/\A([A-Za-z_$][\w$]*)\s*:\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)/)
              (idx.exported_functions[m[1]] ||= [] of Int32) << line_num
            end
            open_cjs_export_buf = combined
          end
          brace_depth += scan.count('{') - scan.count('}')
          next
        end

        # Multi-line `export { a, b }`
        if buf = open_esm_export_buf
          combined = buf + " " + trimmed
          if trimmed.includes?('}')
            parse_esm_export_list(idx, combined)
            open_esm_export_buf = nil
          else
            open_esm_export_buf = combined
          end
          brace_depth += scan.count('{') - scan.count('}')
          next
        end

        if cls = open_class
          if brace_depth == cls.depth + 1
            if trimmed.matches?(/\Aconstructor\s*\(/)
              in_constructor = true
              ctor_params = parse_js_ctor_params(idx, cls, trimmed)
              in_constructor = false if trimmed.includes?(')') && trimmed.includes?('{') && scan.count('{') == scan.count('}')
            elsif m = trimmed.match(/\A(?:(?:public|private|protected|readonly|override|declare)\s+)*([A-Za-z_$][\w$]*)\s*[!?]?\s*:\s*([A-Za-z_$][\w$]*)\b/)
              cls.fields[m[1]] ||= m[2]
            elsif m = trimmed.match(/\A(?:(?:public|private|protected|readonly|static)\s+)*([A-Za-z_$][\w$]*)\s*=\s*new\s+([A-Za-z_$][\w$]*)\b/)
              cls.fields[m[1]] ||= m[2]
            elsif m = trimmed.match(/\A(?:(?:public|private|protected|static|async|override|readonly)\s+)*([A-Za-z_$][\w$]*)\s*(?::[^=]+)?=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::[^=]+)?=>|[A-Za-z_$][\w$]*\s*=>)/)
              (cls.methods[m[1]] ||= [] of Int32) << line_num
            elsif m = trimmed.match(/\A(?:(?:public|private|protected|static|async|override|get|set)\s+)*([A-Za-z_$][\w$]*)\s*(?:<[^>]*>)?\s*\(/)
              mname = m[1]
              unless TRANSITIVE_SKIP_KEYWORDS.includes?(mname)
                (cls.methods[mname] ||= [] of Int32) << line_num
              end
            end
          elsif in_constructor
            parse_js_ctor_params(idx, cls, trimmed) if brace_depth == cls.depth + 1
            if m = trimmed.match(/\Athis\.([A-Za-z_$][\w$]*)\s*=\s*([A-Za-z_$][\w$]*)\s*;?\z/)
              if ptype = ctor_params[m[2]]?
                cls.fields[m[1]] ||= ptype
              end
            end
          end

          brace_depth += scan.count('{') - scan.count('}')
          if brace_depth <= cls.depth
            open_class = nil
            in_constructor = false
          elsif in_constructor && brace_depth <= cls.depth + 1 && !trimmed.matches?(/\Aconstructor\s*\(/)
            in_constructor = false
          end
          next
        end

        if brace_depth == 0 && !trimmed.empty?
          if trimmed.starts_with?("import ")
            if trimmed.includes?('{') && !trimmed.matches?(/\bfrom\s+['"][^'"]+['"]/)
              open_import_buf = trimmed
            else
              parse_js_import_statement(idx, trimmed)
            end
          elsif trimmed.matches?(/\A(?:const|let|var)\s+.*=\s*require\s*\(/)
            parse_cjs_require(idx, trimmed)
          elsif m = trimmed.match(/\A(export\s+(default\s+)?)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)?/)
            is_default = !m[2]?.nil?
            cname = m[3]?
            cls = JsClassInfo.new(cname, line_num, brace_depth)
            if cname
              idx.classes[cname] = cls unless idx.classes.has_key?(cname)
              idx.class_list << cls
              idx.default_export_name ||= cname if is_default
            end
            idx.default_export_class ||= cls if is_default
            if scan.includes?('{') && (brace_depth + scan.count('{') - scan.count('}')) > brace_depth
              open_class = cls
            end
          elsif m = trimmed.match(/\A(export\s+(default\s+)?)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)\s*(?:<[^>]*>)?\s*\(/)
            fname = m[3]
            (idx.top_functions[fname] ||= [] of Int32) << line_num
            (idx.exported_functions[fname] ||= [] of Int32) << line_num if m[1]?
            idx.default_export_line ||= line_num if m[2]?
          elsif m = trimmed.match(/\A(export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*(?::[^=]+)?=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*(?::[^=]+)?=>|[A-Za-z_$][\w$]*\s*=>)/)
            fname = m[2]
            (idx.top_functions[fname] ||= [] of Int32) << line_num
            (idx.exported_functions[fname] ||= [] of Int32) << line_num if m[1]?
          elsif m = trimmed.match(/\A(?:module\.)?exports\.([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?(?:function\b|\([^)]*\)\s*=>|[A-Za-z_$][\w$]*\s*=>)/)
            (idx.exported_functions[m[1]] ||= [] of Int32) << line_num
          elsif m = trimmed.match(/\A(?:module\.)?exports\.([A-Za-z_$][\w$]*)\s*=\s*([A-Za-z_$][\w$]*)\s*;?\z/)
            idx.export_aliases[m[1]] = m[2]
          elsif trimmed.matches?(/\Amodule\.exports\s*=\s*\{/)
            if trimmed.includes?('}')
              parse_cjs_exports_block(idx, trimmed, line_num)
            else
              open_cjs_export_buf = trimmed
            end
          elsif m = trimmed.match(/\Amodule\.exports\s*=\s*([A-Za-z_$][\w$]*)\s*;?\z/)
            idx.default_export_name ||= m[1]
          elsif m = trimmed.match(/\Aexport\s+default\s+([A-Za-z_$][\w$]*)\s*;?\z/)
            idx.default_export_name ||= m[1]
          elsif trimmed.matches?(/\Aexport\s*\{/)
            if trimmed.includes?('}')
              parse_esm_export_list(idx, trimmed)
            else
              open_esm_export_buf = trimmed
            end
          end
        end

        brace_depth += scan.count('{') - scan.count('}')
      end

      @js_indexes[path] = idx
    end

    private def parse_js_ctor_params(idx : JsFileIndex, cls : JsClassInfo, text : String) : Hash(String, String)
      params = {} of String => String
      inner = text.sub(/\A.*?constructor\s*\(/, "")
      inner = inner.split(')', 2)[0]
      inner.split(',').each do |part|
        cleaned = part.gsub(/@[A-Za-z_$][\w$]*(?:\([^)]*\))?\s*/, "").strip
        if m = cleaned.match(/\A((?:public|private|protected|readonly)\s+)*([A-Za-z_$][\w$]*)\s*[!?]?\s*:\s*([A-Za-z_$][\w$]*)\b/)
          param_name = m[2]
          type_name = m[3]
          params[param_name] = type_name
          cls.fields[param_name] ||= type_name if m[1]?
        end
      end
      params
    end

    private def parse_js_import_statement(idx : JsFileIndex, stmt : String)
      return unless m = stmt.match(/\Aimport\s+(?:type\s+)?(.+?)\s+from\s+['"]([^'"]+)['"]/)

      clause = m[1].strip
      specifier = m[2]

      if ns = clause.match(/\A\*\s+as\s+([A-Za-z_$][\w$]*)\z/)
        idx.namespace_imports[ns[1]] = specifier
        return
      end

      if brace_start = clause.index('{')
        before = clause[0...brace_start].rstrip(',').strip
        if before.matches?(/\A[A-Za-z_$][\w$]*\z/)
          idx.default_imports[before] = specifier
        end
        if brace_end = clause.index('}', brace_start)
          clause[(brace_start + 1)...brace_end].split(',').each do |item|
            entry = item.strip.sub(/\Atype\s+/, "")
            next if entry.empty?
            if am = entry.match(/\A([A-Za-z_$][\w$]*)\s+as\s+([A-Za-z_$][\w$]*)\z/)
              idx.named_imports[am[2]] = JsNamedImport.new(specifier, am[1])
            elsif entry.matches?(/\A[A-Za-z_$][\w$]*\z/)
              idx.named_imports[entry] = JsNamedImport.new(specifier, entry)
            end
          end
        end
      elsif clause.matches?(/\A[A-Za-z_$][\w$]*\z/)
        idx.default_imports[clause] = specifier
      end
    end

    private def parse_cjs_require(idx : JsFileIndex, stmt : String)
      return unless m = stmt.match(/\A(?:const|let|var)\s+(.+?)\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)(?:\.([A-Za-z_$][\w$]*))?/)

      lhs = m[1].strip
      specifier = m[2]
      member = m[3]?

      if member
        if lhs.matches?(/\A[A-Za-z_$][\w$]*\z/)
          idx.named_imports[lhs] = JsNamedImport.new(specifier, member)
        end
        return
      end

      if lhs.starts_with?('{') && lhs.ends_with?('}')
        lhs[1...-1].split(',').each do |item|
          entry = item.strip
          next if entry.empty?
          if am = entry.match(/\A([A-Za-z_$][\w$]*)\s*:\s*([A-Za-z_$][\w$]*)\z/)
            idx.named_imports[am[2]] = JsNamedImport.new(specifier, am[1])
          elsif entry.matches?(/\A[A-Za-z_$][\w$]*\z/)
            idx.named_imports[entry] = JsNamedImport.new(specifier, entry)
          end
        end
      elsif lhs.matches?(/\A[A-Za-z_$][\w$]*\z/)
        idx.namespace_imports[lhs] = specifier
        idx.default_imports[lhs] = specifier
      end
    end

    private def parse_cjs_exports_block(idx : JsFileIndex, text : String, base_line : Int32)
      return unless m = text.match(/\{([\s\S]*)\}/)

      m[1].split(',').each do |item|
        entry = item.strip
        next if entry.empty?
        if am = entry.match(/\A([A-Za-z_$][\w$]*)\s*:\s*([A-Za-z_$][\w$]*)\z/)
          idx.export_aliases[am[1]] = am[2]
        elsif entry.matches?(/\A[A-Za-z_$][\w$]*\z/)
          idx.export_aliases[entry] = entry
        end
      end
    end

    private def parse_esm_export_list(idx : JsFileIndex, text : String)
      return unless m = text.match(/\{([^}]*)\}/)

      m[1].split(',').each do |item|
        entry = item.strip
        next if entry.empty?
        if am = entry.match(/\A([A-Za-z_$][\w$]*)\s+as\s+([A-Za-z_$][\w$]*)\z/)
          idx.export_aliases[am[2]] = am[1]
        elsif entry.matches?(/\A[A-Za-z_$][\w$]*\z/)
          idx.export_aliases[entry] = entry
        end
      end
    end

    private def resolve_js_module(caller_path : String, specifier : String) : String?
      files = js_files_map
      return if files.empty?

      if specifier.starts_with?("./") || specifier.starts_with?("../")
        caller_dir = Path.new(caller_path).normalize.dirname
        base = Path.new(caller_dir, specifier).normalize.to_s
        return match_js_candidates(files, base)
      end

      # Support `@/...` / `~/...` / `src/...` project-internal path aliases when unique
      rel = if specifier.starts_with?("@/") || specifier.starts_with?("~/")
              specifier[2..]
            elsif specifier.includes?('/') && !specifier.starts_with?('@')
              specifier
            else
              return
            end

      candidates = JS_TS_EXTS.flat_map { |ext| ["/#{rel}#{ext}", "/#{rel}/index#{ext}", "#{rel}#{ext}", "#{rel}/index#{ext}"] }
      matches = [] of String
      files.each do |norm, orig|
        next if norm.includes?(".test.") || norm.includes?(".spec.")
        if candidates.any? { |cand| cand.starts_with?('/') ? norm.ends_with?(cand) : norm == cand }
          matches << orig
        end
      end
      matches.size == 1 ? matches[0] : nil
    end

    private def match_js_candidates(files : Hash(String, String), base : String) : String?
      if found = files[base]?
        return found
      end

      # ESM TS imports often write `./foo.js` for `./foo.ts`
      if base.ends_with?(".js") || base.ends_with?(".jsx") || base.ends_with?(".mjs") || base.ends_with?(".cjs")
        stem = base[0...base.rindex!('.')]
        %w[.ts .tsx .mts .cts].each do |ts_ext|
          if found = files["#{stem}#{ts_ext}"]?
            return found
          end
        end
      end

      JS_TS_EXTS.each do |ext|
        if found = files["#{base}#{ext}"]?
          return found
        end
      end
      JS_TS_EXTS.each do |ext|
        if found = files["#{base}/index#{ext}"]?
          return found
        end
      end
      nil
    end

    private def resolve_js_callee(name : String,
                                  caller_path : String,
                                  caller_line : Int32,
                                  enclosing_def_line : Int32?) : Tuple(String, Int32)?
      parts = name.split('.')
      return if parts.empty?

      idx = js_file_index(caller_path)
      case parts.size
      when 1
        fn = parts[0]
        if imp = idx.named_imports[fn]?
          return unless target_path = resolve_js_module(caller_path, imp.specifier)
          return resolve_js_exported_fn(target_path, imp.symbol)
        elsif spec = idx.default_imports[fn]?
          return unless target_path = resolve_js_module(caller_path, spec)
          target_idx = js_file_index(target_path)
          if dline = target_idx.default_export_line
            return {target_path, dline}
          elsif dname = target_idx.default_export_name
            lines = target_idx.top_functions[dname]?
            return lines && lines.size == 1 ? {target_path, lines[0]} : nil
          end
          return
        end
        lines = idx.top_functions[fn]?
        lines && lines.size == 1 ? {caller_path, lines[0]} : nil
      when 2
        recv, meth = parts[0], parts[1]
        if recv == "this"
          return unless cls = enclosing_js_class(idx, caller_line)
          lines = cls.methods[meth]?
          return lines && lines.size == 1 ? {caller_path, lines[0]} : nil
        end

        if spec = idx.namespace_imports[recv]? || idx.default_imports[recv]?
          return unless target_path = resolve_js_module(caller_path, spec)
          return resolve_js_exported_member(target_path, meth)
        end

        if type_name = js_local_var_type(caller_path, caller_line, enclosing_def_line, recv)
          return resolve_js_class_method(caller_path, idx, type_name, meth)
        end
        nil
      when 3
        if parts[0] == "this"
          return unless cls = enclosing_js_class(idx, caller_line)
          return unless type_name = cls.fields[parts[1]]?
          return resolve_js_class_method(caller_path, idx, type_name, parts[2])
        end
        nil
      end
    end

    private def resolve_js_exported_fn(target_path : String, symbol : String) : Tuple(String, Int32)?
      target_idx = js_file_index(target_path)
      if lines = target_idx.exported_functions[symbol]?
        return lines.size == 1 ? {target_path, lines[0]} : nil
      end
      if alias_target = target_idx.export_aliases[symbol]?
        lines = target_idx.top_functions[alias_target]? || target_idx.exported_functions[alias_target]?
        return lines && lines.size == 1 ? {target_path, lines[0]} : nil
      end
      # Fallback if function was exported via `module.exports = { ... }` or `export`
      if lines = target_idx.top_functions[symbol]?
        if target_idx.export_aliases.has_key?(symbol) || target_idx.exported_functions.has_key?(symbol)
          return lines.size == 1 ? {target_path, lines[0]} : nil
        end
      end
      nil
    end

    private def resolve_js_exported_member(target_path : String, member : String) : Tuple(String, Int32)?
      if found = resolve_js_exported_fn(target_path, member)
        return found
      end

      target_idx = js_file_index(target_path)
      if cls = target_idx.default_export_class
        lines = cls.methods[member]?
        return lines && lines.size == 1 ? {target_path, lines[0]} : nil
      elsif dname = target_idx.default_export_name
        if cls = target_idx.classes[dname]?
          lines = cls.methods[member]?
          return lines && lines.size == 1 ? {target_path, lines[0]} : nil
        end
      end
      nil
    end

    private def resolve_js_class_method(caller_path : String,
                                        caller_idx : JsFileIndex,
                                        type_name : String,
                                        method_name : String) : Tuple(String, Int32)?
      if cls = caller_idx.classes[type_name]?
        lines = cls.methods[method_name]?
        return lines && lines.size == 1 ? {caller_path, lines[0]} : nil
      end

      if imp = caller_idx.named_imports[type_name]?
        return unless target_path = resolve_js_module(caller_path, imp.specifier)
        if cls = js_file_index(target_path).classes[imp.symbol]?
          lines = cls.methods[method_name]?
          return lines && lines.size == 1 ? {target_path, lines[0]} : nil
        end
      elsif spec = caller_idx.default_imports[type_name]?
        return unless target_path = resolve_js_module(caller_path, spec)
        target_idx = js_file_index(target_path)
        cls = target_idx.default_export_class ||
              target_idx.default_export_name.try { |dn| target_idx.classes[dn]? } ||
              target_idx.classes[type_name]?
        if cls
          lines = cls.methods[method_name]?
          return lines && lines.size == 1 ? {target_path, lines[0]} : nil
        end
      end
      nil
    end

    private def enclosing_js_class(idx : JsFileIndex, line : Int32) : JsClassInfo?
      best : JsClassInfo? = nil
      idx.class_list.each do |cls|
        break if cls.line >= line
        best = cls
      end
      best
    end

    private def js_local_var_type(path : String, line : Int32, enclosing_def_line : Int32?, var_name : String) : String?
      lines = @reader.lines_for(path)
      return if line < 1 || line > lines.size

      ext = File.extname(path).downcase
      esc = Regex.escape(var_name)
      stop_line = enclosing_def_line || 1

      depth = 0
      depths = Array(Int32).new(line, 0)
      0.upto(line - 1) do |i|
        depths[i] = depth
        _, scan, _ = strip_line_comments_and_strings(lines[i], ext, false)
        depth += scan.count('{') - scan.count('}')
      end
      min_depth = depths[line - 1]

      (line - 2).downto(Math.max(stop_line - 1, 0)) do |i|
        next if depths[i] > min_depth
        min_depth = depths[i]

        code = strip_line_comments_and_strings(lines[i], ext, false)[0].strip
        next if code.empty?

        if m = code.match(/\A(?:const|let|var)\s+#{esc}\s*(?::\s*([A-Za-z_$][\w$]*))?\s*=\s*new\s+([A-Za-z_$][\w$]*)\b/)
          return m[1]? || m[2]
        elsif m = code.match(/\A(?:const|let|var)\s+#{esc}\s*:\s*([A-Za-z_$][\w$]*)\b/)
          return m[1]
        elsif m = code.match(/\b#{esc}\s*:\s*([A-Za-z_$][\w$]*)\b/)
          return m[1] if i == stop_line - 1
        end
      end
      nil
    end
  end
end
