require "../../engines/scala_engine"

module Analyzer::Scala
  class Tapir < ScalaEngine
    HTTP_METHODS = %w[get post put delete patch head options connect trace]

    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile) — precompile the fixed per-verb matchers
    # once at load time instead of per chain.
    METHOD_CALL_PATTERNS = HTTP_METHODS.map do |m|
      {m, /\.#{m}\b/}
    end

    BASE_ENDPOINT_RE = /(?<![.\w])(?:[A-Za-z_]\w*[Ee]ndpoint|endpoint|infallibleEndpoint)\b/

    # Leading `val NAME [: TYPE] =` of a definition. Group 1 captures the name;
    # `match.end` marks where the right-hand side (the actual endpoint chain)
    # begins. `=(?![=>])` avoids stopping on `==`/`=>`.
    VAL_DEF_RE = /^\s*(?:(?:private|protected|implicit|lazy|final|override)\s+)*val\s+(\w+)\s*(?::\s*[^=]+?\s*)?=(?![=>])\s*/

    MODIFIERS = "(?:(?:private|protected|implicit|lazy|final|override)\\s+)*"

    # `val UserPath = "user"` (optionally `/`-joined literals). The captured
    # value is already in literal form, so substituting it back into a `.in(...)`
    # block lets the normal path-literal scan pick up the segments.
    PATH_CONST_RE = Regex.new(
      "^\\s*#{MODIFIERS}val\\s+(\\w+)\\s*(?::\\s*String\\s*)?=\\s*" \
      "(\"(?:[^\"\\\\]|\\\\.)*\"(?:\\s*/\\s*\"(?:[^\"\\\\]|\\\\.)*\")*)\\s*$"
    )

    # `val limitParameter = query[Option[Int]]("limit")...` — a reusable input
    # combinator bound to a val. Only the combinator core is captured so any
    # trailing `.description(...)` is dropped.
    PARAM_CONST_RE = Regex.new(
      "^\\s*#{MODIFIERS}val\\s+(\\w+)\\s*=\\s*" \
      "((?:query|queries|header|cookie|path)\\[#{TYPE_PATTERN}\\]\\s*\\(\\s*\"[^\"]+\"\\s*\\)" \
      "|header\\s*\\(\\s*\"[^\"]+\"\\s*\\))"
    )

    # Type token allows one level of nested brackets (e.g. Option[String], List[User]).
    TYPE_PATTERN = "(?:[^\\[\\]]|\\[[^\\[\\]]*\\])+"

    IN_TOKEN_RE = Regex.new(
      "\"(?<literal>[^\"]+)\"" \
      "|path\\[(?<path_type>#{TYPE_PATTERN})\\](?:\\s*\\(\\s*\"(?<path_name>[^\"]+)\"\\s*\\))?" \
      "|query\\[(?<query_type>#{TYPE_PATTERN})\\]\\s*\\(\\s*\"(?<query_name>[^\"]+)\"\\s*\\)" \
      "|queries\\[(?<queries_type>#{TYPE_PATTERN})\\]\\s*\\(\\s*\"(?<queries_name>[^\"]+)\"\\s*\\)" \
      "|header\\[(?<header_type>#{TYPE_PATTERN})\\]\\s*\\(\\s*\"(?<header_name>[^\"]+)\"\\s*\\)" \
      "|header\\s*\\(\\s*\"(?<header_name2>[^\"]+)\"" \
      "|cookie\\[(?<cookie_type>#{TYPE_PATTERN})\\]\\s*\\(\\s*\"(?<cookie_name>[^\"]+)\"\\s*\\)" \
      "|(?<body>jsonBody|xmlBody|stringBody|plainBody|binaryBody|byteArrayBody|byteBufferBody|formBody|multipartBody|rawBinaryBody|fileBody)(?:\\[(?<body_type>#{TYPE_PATTERN})\\])?"
    )

    def analyze_file(path : String) : Array(Endpoint)
      content = File.read(path)
      extract_routes_from_content(path, content)
    end

    # One collected endpoint chain. `name` is the `val` it was assigned to (if
    # any) so other chains can reuse it as a base for prefix composition.
    private record Chain, name : String?, text : String, line : Int32

    private def extract_routes_from_content(path : String, content : String) : Array(Endpoint)
      lexer = scala_lexer(content)
      code_lines = lexer.code_lines
      struct_lines = lexer.masked_lines

      chains = collect_chains(code_lines, struct_lines)

      # Map every named chain so a later chain that starts from one of them
      # (e.g. `val addBook = baseEndpoint.post...`) can inherit its path prefix.
      defs = {} of String => String
      chains.each { |c| (n = c.name) && (defs[n] = c.text) }

      consts = build_consts(code_lines)
      cache = {} of String => Tuple(Array(String), Array(Param))
      endpoints = [] of Endpoint
      chains.each do |chain|
        method = detect_method(chain.text)
        next unless method

        endpoint = create_endpoint("/", method.upcase, path, chain.line)
        seen = Set(String).new
        (n = chain.name) && (seen << n)
        segments, params = resolve_chain(chain.text, defs, consts, cache, seen)
        endpoint.url = segments.empty? ? "/" : "/" + segments.join("/")
        params.each { |p| add_param(endpoint, p.name, p.value, p.param_type) }
        endpoints << endpoint
      end

      endpoints
    end

    private def collect_chains(code_lines : Array(String), struct_lines : Array(String)) : Array(Chain)
      chains = [] of Chain
      consumed_until = -1
      code_lines.each_index do |index|
        next if index <= consumed_until
        code = code_lines[index]? || ""

        # Skip the `val NAME [: TYPE] =` prefix so a val whose name (or type
        # annotation, e.g. `PublicEndpoint[...]`) ends in "Endpoint" doesn't
        # get matched in place of the RHS base token. The captured name lets the
        # chain be reused as a base for prefix composition.
        name = nil
        search_offset = 0
        if vm = code.match(VAL_DEF_RE)
          name = vm[1]
          search_offset = vm.end
        end

        masked = struct_lines[index]? || ""
        col = base_match_col(code, masked, search_offset)
        next unless col
        chain_text, last_line = collect_chain(code_lines, struct_lines, index, col)
        consumed_until = last_line
        chains << Chain.new(name, chain_text, index + 1)
      end
      chains
    end

    # Resolve a chain's path segments and params, prepending those of the base
    # endpoint it was derived from. `endpoint`/`infallibleEndpoint` are the
    # terminal roots; any other leading identifier that names a known chain is a
    # reusable base (`val base = endpoint.in("books")`). `seen` guards cycles.
    private def resolve_chain(chain : String, defs : Hash(String, String),
                              consts : Hash(String, String),
                              cache : Hash(String, Tuple(Array(String), Array(Param))),
                              seen : Set(String)) : Tuple(Array(String), Array(Param))
      own_segments = [] of String
      own_params = [] of Param
      extract_in_blocks(chain).each do |args|
        process_in_args(args, own_params, own_segments, consts)
      end

      head = leading_ident(chain)
      if head && head != "endpoint" && head != "infallibleEndpoint" && !seen.includes?(head) && (base_chain = defs[head]?)
        base_segs, base_params = cache[head]? || begin
          resolved = resolve_chain(base_chain, defs, consts, cache, seen | Set{head})
          cache[head] = resolved
          resolved
        end
        return {base_segs + own_segments, base_params + own_params}
      end

      {own_segments, own_params}
    end

    # Collect `val NAME = "literal"` path constants and `val NAME = query[..](..)`
    # input-combinator constants so a `.in(NAME / ...)` reference resolves to the
    # real path/param instead of being dropped.
    private def build_consts(code_lines : Array(String)) : Hash(String, String)
      consts = {} of String => String
      code_lines.each do |line|
        next if line.empty?
        if m = line.match(PATH_CONST_RE)
          consts[m[1]] = m[2]
        elsif m = line.match(PARAM_CONST_RE)
          consts[m[1]] = m[2]
        end
      end
      consts
    end

    private def leading_ident(chain : String) : String?
      m = chain.match(/^\s*([A-Za-z_]\w*)/)
      m ? m[1] : nil
    end

    # Column of the first real base-endpoint token at/after `offset`, skipping
    # matches that sit inside a `[...]` type-argument list (e.g. the type name in
    # `List[ServerEndpoint[Any, F]](...)`). Such a match would otherwise start a
    # chain whose head carries an unbalanced `(` from the enclosing call and
    # swallow the following endpoint lines. `secureEndpoint[ApiKey].post` is kept
    # because the identifier itself is at bracket depth 0.
    private def base_match_col(code : String, masked : String, offset : Int32) : Int32?
      while m = code.match(BASE_ENDPOINT_RE, offset)
        col = m.begin || 0
        prefix = col <= masked.size ? masked[0...col] : masked
        bracket_depth = prefix.count('[') - prefix.count(']')
        return col if bracket_depth <= 0
        offset = col + m[0].size
      end
      nil
    end

    # Collect a Tapir endpoint chain spanning multiple lines. A line is part of
    # the chain when it continues an open `(` (a multi-line `.in(...)` argument)
    # OR begins with `.` (a chained combinator). Paren depth is counted on the
    # structural view so parens inside string literals don't skew the balance.
    private def collect_chain(code_lines : Array(String), struct_lines : Array(String), start : Int32, col : Int32) : Tuple(String, Int32)
      head_code = code_lines[start]? || ""
      head_struct = struct_lines[start]? || ""
      first = col < head_code.size ? head_code[col..] : ""
      first_struct = col < head_struct.size ? head_struct[col..] : ""
      parts = [first]
      depth = paren_balance(first_struct)
      idx = start + 1
      while idx < code_lines.size
        code = code_lines[idx]? || ""
        masked = struct_lines[idx]? || ""
        if depth > 0
          parts << code
          depth += paren_balance(masked)
          idx += 1
        elsif code.lstrip.starts_with?(".")
          parts << code
          depth += paren_balance(masked)
          idx += 1
        else
          break
        end
      end
      {parts.join("\n"), idx - 1}
    end

    private def paren_balance(s : String) : Int32
      s.count('(') - s.count(')')
    end

    # Number of open *call* parens just before each character, ignoring parens
    # inside string literals. A `(` is a call paren when it directly follows an
    # identifier / `]` (e.g. `example(`, `path[String](`); a `(` after an
    # operator, whitespace or start is a grouping paren and does not count. This
    # lets a literal inside `("a" / b)` stay a path segment while one inside
    # `.example("a")` is rejected.
    private def call_paren_depths(s : String) : Array(Int32)
      depths = Array(Int32).new(s.size, 0)
      call_depth = 0
      stack = [] of Bool
      in_str = false
      prev_sig = '\0'
      i = 0
      while i < s.size
        depths[i] = call_depth
        c = s[i]
        if in_str
          if c == '\\'
            depths[i + 1] = call_depth if i + 1 < s.size
            i += 2
            next
          elsif c == '"'
            in_str = false
            prev_sig = '"'
          end
        else
          case c
          when '"'
            in_str = true
            prev_sig = '"'
          when '('
            is_call = prev_sig.ascii_alphanumeric? || prev_sig == '_' || prev_sig == ']'
            stack << is_call
            call_depth += 1 if is_call
            prev_sig = '('
          when ')'
            if last = stack.pop?
              call_depth -= 1 if last
            end
            prev_sig = ')'
          else
            prev_sig = c unless c.ascii_whitespace?
          end
        end
        i += 1
      end
      depths
    end

    private def detect_method(chain : String) : String?
      METHOD_CALL_PATTERNS.each do |m, pattern|
        return m if chain.matches?(pattern)
      end

      if mm = chain.match(/\.method\s*\(\s*Method\.([A-Z]+)\s*\)/)
        candidate = mm[1].downcase
        return candidate if HTTP_METHODS.includes?(candidate)
      end

      nil
    end

    private def extract_in_blocks(chain : String) : Array(String)
      blocks = [] of String
      i = 0
      while i < chain.size
        slice = chain[i..]
        if slice.starts_with?(".in(") || slice.starts_with?(".securityIn(")
          open_paren = chain.index('(', i)
          if open_paren && (result = balanced_paren_content(chain, open_paren))
            blocks << result[0]
            i = result[1] + 1
            next
          end
        end
        i += 1
      end
      blocks
    end

    private def balanced_paren_content(s : String, open_idx : Int32) : Tuple(String, Int32)?
      depth = 0
      i = open_idx
      content_start = open_idx + 1
      while i < s.size
        c = s[i]
        if c == '('
          depth += 1
        elsif c == ')'
          depth -= 1
          return {s[content_start...i], i} if depth == 0
        end
        i += 1
      end
      nil
    end

    private def process_in_args(args : String, params : Array(Param), segments : Array(String), consts : Hash(String, String))
      args = substitute_consts(args, consts) unless consts.empty?
      depths = call_paren_depths(args)
      args.scan(IN_TOKEN_RE) do |m|
        if literal = m["literal"]?
          # A string is a path segment only when it is NOT an argument to a
          # method call. `.example("...")` / `.description("...")` chained onto a
          # combinator must not leak into the path, but grouping parens used for
          # input composition — `("a" / path[..]).and(..)` — keep their literals.
          pos = m.begin || 0
          next unless (depths[pos]? || 0) == 0
          literal.split('/').reject(&.empty?).each { |seg| segments << seg }
        elsif m["path_type"]?
          name = m["path_name"]? || default_path_name(segments)
          segments << "{#{name}}"
          collect_param(params, name, "", "path")
        elsif q = m["query_name"]?
          collect_param(params, q, m["query_type"]? || "", "query")
        elsif q = m["queries_name"]?
          collect_param(params, q, m["queries_type"]? || "", "query")
        elsif h = m["header_name"]?
          collect_param(params, h, m["header_type"]? || "", "header")
        elsif h = m["header_name2"]?
          collect_param(params, h, "", "header")
        elsif c = m["cookie_name"]?
          collect_param(params, c, m["cookie_type"]? || "", "cookie")
        elsif body = m["body"]?
          inner = m["body_type"]? || ""
          param_type = case body
                       when "jsonBody"      then "json"
                       when "xmlBody"       then "xml"
                       when "formBody"      then "form"
                       when "multipartBody" then "form"
                       else
                         "body"
                       end
          collect_param(params, "body", inner, param_type)
        end
      end
    end

    private def collect_param(params : Array(Param), name : String, type_value : String, param_type : String)
      return if params.any? { |p| p.name == name && p.param_type == param_type }
      params << Param.new(name, type_value, param_type)
    end

    # Replace top-level identifier references to known path/param constants with
    # their literal/combinator form before tokenizing. Only substitutes outside
    # any call parens or `[...]` type args, and never a `.member`/`call(` — so a
    # const name reused as a type or modifier argument is left untouched.
    private def substitute_consts(args : String, consts : Hash(String, String)) : String
      io = String::Builder.new
      i = 0
      size = args.size
      call_depth = 0
      bracket_depth = 0
      stack = [] of Bool
      in_str = false
      prev_sig = '\0'
      while i < size
        c = args[i]
        if in_str
          io << c
          if c == '\\' && i + 1 < size
            io << args[i + 1]
            i += 2
            next
          elsif c == '"'
            in_str = false
            prev_sig = '"'
          end
          i += 1
          next
        end

        case c
        when '"'
          in_str = true
          io << c
          prev_sig = '"'
          i += 1
        when '['
          bracket_depth += 1
          io << c
          prev_sig = '['
          i += 1
        when ']'
          bracket_depth -= 1
          io << c
          prev_sig = ']'
          i += 1
        when '('
          is_call = prev_sig.ascii_alphanumeric? || prev_sig == '_' || prev_sig == ']'
          stack << is_call
          call_depth += 1 if is_call
          io << c
          prev_sig = '('
          i += 1
        when ')'
          if last = stack.pop?
            call_depth -= 1 if last
          end
          io << c
          prev_sig = ')'
          i += 1
        else
          if c.ascii_letter? || c == '_'
            start = i
            while i < size && (args[i].ascii_alphanumeric? || args[i] == '_')
              i += 1
            end
            ident = args[start...i]
            j = i
            while j < size && args[j].ascii_whitespace?
              j += 1
            end
            following = j < size ? args[j] : '\0'
            if call_depth == 0 && bracket_depth == 0 && prev_sig != '.' &&
               following != '(' && following != '.' && (sub = consts[ident]?)
              io << sub
            else
              io << ident
            end
            prev_sig = ident[-1]
          else
            io << c
            prev_sig = c unless c.ascii_whitespace?
            i += 1
          end
        end
      end
      io.to_s
    end

    private def add_param(endpoint : Endpoint, name : String, type_value : String, param_type : String)
      existing = endpoint.params.find { |p| p.name == name && p.param_type == param_type }
      return if existing

      endpoint.push_param(Param.new(name, type_value, param_type))
    end

    private def default_path_name(segments : Array(String)) : String
      anon_count = segments.count(&.starts_with?("{anon"))
      anon_count == 0 ? "anon" : "anon#{anon_count + 1}"
    end

    private def create_endpoint(url : String, method : String, source : String, line_number : Int32)
      details = Details.new(PathInfo.new(source, line_number))
      params = [] of Param
      Endpoint.new(url, method, params, details)
    end
  end
end
