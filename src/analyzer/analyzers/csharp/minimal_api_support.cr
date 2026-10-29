module Analyzer::CSharp::MinimalApiSupport
  MAP_METHODS = %w[Get Post Put Delete Patch Head Options]

  SIMPLE_BINDING_TYPES = Set{
    "bool", "byte", "sbyte", "short", "ushort", "int", "uint", "long", "ulong",
    "float", "double", "decimal", "char", "string", "Guid", "DateTime",
    "DateTimeOffset", "TimeSpan",
  }

  SERVICE_BINDING_TYPES = Set{
    "CancellationToken", "HttpContext", "HttpRequest", "HttpResponse", "ClaimsPrincipal",
    "IServiceProvider", "ILogger", "ILoggerFactory", "LinkGenerator",
  }

  # `Map<Verb>` may carry an explicit generic argument — Carter's
  # `app.MapPut<Person>("/", …)` and the typed `MapGet<T>` helpers some
  # libraries ship. Without the optional `<…>` the route literal was never
  # reached and the registration produced no endpoint at all.
  MAP_VERB_ROUTE_RE = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?Map(Get|Post|Put|Delete|Patch|Head|Options)\s*(?:<[^<>()]*>\s*)?\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?@?"([^"]+)"/m
  MAP_METHODS_RE    = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?MapMethods\s*(?:<[^<>()]*>\s*)?\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?@?"([^"]+)"\s*,\s*([\s\S]+?)(?:=>|\);)/m
  MAP_CALL_RE       = /\bMap(?:Get|Post|Put|Delete|Patch|Head|Options|Methods|HealthChecks|Forwarder)?\s*(?:<[^<>()]*>\s*)?\(/
  MAP_ANY_PREFIX_RE = /\.?\s*Map(?:Get|Post|Put|Delete|Patch|Head|Options|Methods|HealthChecks|Forwarder)?\s*(?:<[^<>()]*>\s*)?\(/
  # `Map(pattern, …)` and the extensions that wrap it with no method filter:
  # `MapHealthChecks("/health")`, YARP's `MapForwarder("/x/{id}", …)`.
  MAP_ANY_METHOD_RE = /\.\s*Map(?:HealthChecks|Forwarder)?\s*\(/
  MAP_ANY_ROUTE_RE  = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?Map(?:HealthChecks|Forwarder)?\s*\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?@?"([^"]+)"/m

  private def analyze_minimal_api_files(include_callee : Bool)
    sources = [] of Tuple(String, String)
    get_files_by_extension(".cs").each do |file|
      next unless File.exists?(file)
      next if Common.csharp_test_path?(base_relative_path(file))

      content = read_file_content(file)
      # Carter modules register minimal-API routes too, but under a module
      # base path this analyzer can't see — `cs_carter` owns them.
      next if Common.carter_module_source?(content)
      sources << {file, content}
    end

    extension_scopes = route_group_extension_scopes(sources)
    sources.each do |file, content|
      next unless minimal_api_source?(content)
      analyze_minimal_api_content(file, content, include_callee, extension_scopes[file]? || [] of ExtensionScope)
    end
  end

  # A `static … MapTodosApi(this RouteGroupBuilder group)` extension method:
  # the routes it registers on `group` take the prefix of whichever
  # `MapGroup(...)` it is called on, possibly from another file —
  #
  #   app.MapGroup("/public/todos").MapTodosApi();
  #   app.MapGroup("/private/todos").MapTodosApi();
  ROUTE_BUILDER_EXTENSION_RE = /\bstatic\s[^;{}()=]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^<>()]*>\s*)?\(\s*this\s+(?:RouteGroupBuilder|IEndpointRouteBuilder|WebApplication)\b/

  # `{body_line_range, caller_prefixes}` of one extension method in a file.
  alias ExtensionScope = Tuple(Range(Int32, Int32), Array(String))

  # Maps each file to its route-builder extension method bodies and the group
  # prefix of every call site of each, so a route inside one is emitted once
  # per caller prefix. Call sites inside another such extension compose with
  # that extension's own caller prefixes.
  private def route_group_extension_scopes(sources : Array(Tuple(String, String))) : Hash(String, Array(ExtensionScope))
    decls = [] of Tuple(String, String, Range(Int32, Int32))
    sources.each do |file, content|
      next unless content.matches?(ROUTE_BUILDER_EXTENSION_RE)
      lexer = Noir::CSharpLexer.new(content)
      code = lexer.code_source
      lines = lexer.code_lines
      masked_lines = lexer.masked_lines
      code.scan(ROUTE_BUILDER_EXTENSION_RE) do |m|
        decl_index = code[0...m.begin].count('\n')
        _, sig_end = build_signature(lines, masked_lines, decl_index)
        body, body_index, _ = extract_callable_body(lines, masked_lines, sig_end)
        next if body.empty?
        decls << {m[1], file, decl_index..(body_index + Math.max(body.count('\n') - 1, 0))}
      end
    end
    scopes = Hash(String, Array(ExtensionScope)).new
    return scopes if decls.empty?

    names = decls.map(&.[0]).uniq!
    call_re = /\.\s*(#{names.map { |n| Regex.escape(n) }.join('|')})\s*(?:<[^<>()]*>\s*)?\(/
    calls = [] of Tuple(String, String, Int32, String)
    sources.each do |file, content|
      next unless content.matches?(call_re)
      lexer = Noir::CSharpLexer.new(content)
      masked = lexer.masked_source
      code = lexer.code_source
      group_prefixes = extract_map_group_prefixes(code)
      masked.scan(call_re) do |m|
        stmt_start = (masked.rindex(/[;{}]/, m.begin) || -1) + 1
        head = code[stmt_start...m.begin]
        local = group_chain_prefix(head, group_prefixes)
        if local.empty? && (receiver = head.match(/([A-Za-z_][A-Za-z0-9_]*)\s*\z/))
          local = group_prefixes[receiver[1]]? || ""
        end
        calls << {m[1], file, masked[0...m.begin].count('\n'), local}
      end
    end

    memo = Hash(String, Array(String)).new
    decls.each do |name, file, range|
      prefixes = extension_caller_prefixes(name, decls, calls, memo, Set(String).new)
      (scopes[file] ||= [] of ExtensionScope) << {range, prefixes}
    end
    scopes
  end

  # ponytail: extensions are keyed by method name, so two same-named
  # extensions share their callers' prefixes; key by declaring type if that
  # ever surfaces.
  private def extension_caller_prefixes(name : String, decls : Array(Tuple(String, String, Range(Int32, Int32))),
                                        calls : Array(Tuple(String, String, Int32, String)),
                                        memo : Hash(String, Array(String)), seen : Set(String)) : Array(String)
    if cached = memo[name]?
      return cached
    end
    return [""] unless seen.add?(name)

    sites = calls.select { |call| call[0] == name }
    return memo[name] = [""] if sites.empty?

    prefixes = sites.flat_map do |_, file, line, local|
      outer = decls.find { |decl| decl[1] == file && decl[2].includes?(line) }
      outer_prefixes = outer ? extension_caller_prefixes(outer[0], decls, calls, memo, seen) : [""]
      outer_prefixes.map { |outer_prefix| join_route_parts(outer_prefix, local) }
    end
    memo[name] = prefixes.uniq.map { |prefix| prefix == "/" ? "" : prefix }
  end

  MINIMAL_API_MARKER_RE = /\.\s*Map(?:Get|Post|Put|Delete|Patch|Head|Options|Methods)\s*(?:<[^<>()]*>\s*)?\(/

  private def minimal_api_source?(content : String) : Bool
    content_matches?(content, MINIMAL_API_MARKER_RE) ||
      (content.matches?(MAP_ANY_METHOD_RE) && minimal_api_context?(content))
  end

  private def minimal_api_context?(content : String) : Bool
    content.includes?("WebApplication") ||
      content.includes?("IEndpointRouteBuilder") ||
      content.includes?("RouteGroupBuilder")
  end

  private def analyze_minimal_api_content(file : String, content : String, include_callee : Bool,
                                          extension_scopes : Array(ExtensionScope) = [] of ExtensionScope)
    lexer = Noir::CSharpLexer.new(content)
    # Scan comment-blanked source: ASP.NET Core's own libraries carry
    # `/// app.MapGet("/from-route/{id}", …)` inside `<example>` XML docs and
    # `// app.MapGet("/form-todo", …)` in explanatory comments, each of which
    # the raw scan emitted as a real endpoint. Line numbers and column offsets
    # are preserved, so reported locations are unchanged.
    lines = lexer.code_lines
    masked_lines = lexer.masked_lines
    group_prefixes = extract_map_group_prefixes(lexer.code_source)

    each_map_block(lines, masked_lines, 0...lines.size, group_prefixes) do |block, index, chain_prefix|
      caller_prefixes = extension_scopes.find(&.[0].includes?(index)).try(&.[1]) || [""]
      caller_prefixes.each do |route_prefix|
        extract_endpoints_from_map_block(block, group_prefixes, file, index + 1, lines, masked_lines,
          include_callee, route_prefix: route_prefix, chain_prefix: chain_prefix).each do |endpoint|
          @result << endpoint
        end
      end
    end
  end

  # Yields `{block, line_index, chain_prefix}` for every `Map*` registration
  # on the lines in `range`, one per statement, so two registrations on one
  # line are both seen. `chain_prefix` carries the `MapGroup` prefix of a
  # chain whose `.Map*` call continues on a leading-dot line:
  #
  #   app.MapGroup("/api")
  #      .MapGet("/items", ...);
  private def each_map_block(lines : Array(String), masked_lines : Array(String), range : Range(Int32, Int32),
                             group_prefixes : Hash(String, String), &)
    chain_prefix = ""
    range.each do |index|
      line = lines[index]
      masked = masked_lines[index]? || line
      # A comment or blank line inside a chain does not end it.
      next if masked.blank?
      continuation = masked.lstrip.starts_with?('.')
      chain_prefix = "" unless continuation
      if route_builder_line?(line)
        starts = map_statement_starts(masked)
        start_chars = {line.chars, masked.chars} if starts.size > 1
        starts.each do |column|
          prefix = column == 0 && continuation ? chain_prefix : ""
          yield extract_map_block(lines, masked_lines, index, column, start_chars), index, prefix
        end
      end
      next unless line.includes?("MapGroup")
      # Both sides are already normalized (`/a`, `/a/b`), so a plain append
      # joins them without re-normalizing the whole chain on every line.
      line_prefix = group_chain_prefix(line, group_prefixes).rchop("/")
      chain_prefix = continuation ? chain_prefix + line_prefix : line_prefix
    end
  end

  # Start column of each statement on `masked` that holds a `Map*` call. A
  # statement ends at a `;` outside the line's parens and braces.
  private def map_statement_starts(masked : String) : Array(Int32)
    starts = [] of Int32
    start = 0
    depth = 0
    segment = String::Builder.new
    masked.each_char_with_index do |char, column|
      segment << char
      case char
      when '(', '{' then depth += 1
      when ')', '}' then depth -= 1
      when ';'
        next if depth > 0
        starts << start if route_builder_line?(segment.to_s)
        segment = String::Builder.new
        start = column + 1
        depth = 0
      end
    end
    starts << start if start < masked.size && route_builder_line?(segment.to_s)
    starts
  end

  private def route_builder_line?(line : String) : Bool
    MAP_METHODS.any? { |verb| line.includes?("Map#{verb}") } ||
      line.includes?("MapMethods") ||
      line.matches?(MAP_ANY_METHOD_RE)
  end

  private def extract_endpoints_from_map_block(block : String,
                                               group_prefixes : Hash(String, String),
                                               file : String,
                                               line : Int32,
                                               file_lines : Array(String),
                                               masked_lines : Array(String),
                                               include_callee : Bool,
                                               route_prefix : String = "",
                                               chain_prefix : String = "") : Array(Endpoint)
    route, methods = extract_route_and_methods(block, group_prefixes, chain_prefix)
    return [] of Endpoint unless route && methods.size > 0

    route = join_route_parts(route_prefix, route) unless route_prefix.empty?

    consts = string_consts(file_lines) if block.matches?(CONST_REFERENCE_RE)
    extra_params = extract_params_from_block(block, consts)
    extra_params.concat(extract_bind_params_from_file(block, file_lines, masked_lines))
    extra_params.concat(extract_delegate_params(block, route, methods.first, file, file_lines, masked_lines))

    # Method-group handlers — `MapGet("/items", GetItems)` — carry the route
    # on the `Map` line but keep their parameters and body in the referenced
    # method. Resolve it so params, callees and ai-context aren't lost. The
    # dominant style in modern minimal APIs (eShop, vertical-slice/REPR).
    callee_block = block
    callee_line = line
    callee_skip_first = false
    handler_ref = nil
    if handler = resolve_handler_method(block, file_lines, masked_lines)
      name, sig, handler_block, handler_line, skip_first, decl_line = handler
      extra_params.concat(handler_signature_params(sig, route, methods.first, file, file_lines, masked_lines))
      consts ||= string_consts(file_lines) if handler_block.matches?(CONST_REFERENCE_RE)
      extra_params.concat(extract_params_from_block(handler_block, consts))
      callee_block = handler_block
      callee_line = handler_line
      callee_skip_first = skip_first
      handler_ref = Handler.new(name, file, decl_line)
    elsif lambda_line = lambda_handler_line(block, line)
      handler_ref = Handler.new("closure", file, lambda_line)
    end

    endpoints = [] of Endpoint
    methods.each do |method|
      endpoint = build_endpoint_from_route(route, method, file, line, extra_params)
      next unless endpoint

      attach_csharp_callees(endpoint, callee_block, file, callee_line, include_callee, skip_first_line: callee_skip_first)
      endpoint.handler = handler_ref
      endpoints << endpoint
    end
    endpoints
  end

  private def extract_route_and_methods(block : String, group_prefixes : Hash(String, String), chain_prefix : String = "") : Tuple(String?, Array(String))
    if block.includes?("MapMethods")
      route, methods = extract_map_methods_route(block, group_prefixes, chain_prefix)
      return {route, methods}
    end

    inline_prefix = extract_inline_group_prefix(block, group_prefixes, chain_prefix)
    if match = block.match(MAP_VERB_ROUTE_RE)
      receiver = match[1]?
      route = apply_group_prefix(match[3], receiver, group_prefixes)
      route = join_route_parts(inline_prefix, route) unless inline_prefix.empty?
      return {route, [match[2].upcase]}
    end

    if match = block.match(MAP_ANY_ROUTE_RE)
      receiver = match[1]?
      route = apply_group_prefix(match[2], receiver, group_prefixes)
      route = join_route_parts(inline_prefix, route) unless inline_prefix.empty?
      return {route, ["ANY"]}
    end

    {nil, [] of String}
  end

  private def extract_map_methods_route(block : String, group_prefixes : Hash(String, String), chain_prefix : String) : Tuple(String?, Array(String))
    inline_prefix = extract_inline_group_prefix(block, group_prefixes, chain_prefix)

    if match = block.match(MAP_METHODS_RE)
      receiver = match[1]?
      route = apply_group_prefix(match[2], receiver, group_prefixes)
      route = join_route_parts(inline_prefix, route) unless inline_prefix.empty?
      methods = extract_http_methods(match[3])
      return {route, methods}
    end

    {nil, [] of String}
  end

  private def extract_http_methods(section : String) : Array(String)
    methods = section.scan(/"([A-Za-z]+)"/).map(&.[1]?.to_s.upcase).reject(&.empty?)

    section.scan(/HttpMethods\.([A-Za-z]+)/) do |match|
      method = match[1]?.to_s.upcase
      methods << method unless method.empty?
    end

    methods.uniq
  end

  private def extract_inline_group_prefix(block : String, group_prefixes : Hash(String, String), chain_prefix : String = "") : String
    map_index = block.index(MAP_ANY_PREFIX_RE)
    return "" unless map_index

    own_prefix = group_chain_prefix(block[0...map_index], group_prefixes)
    return own_prefix if chain_prefix.empty?
    return chain_prefix if own_prefix.empty?
    join_route_parts(chain_prefix, own_prefix)
  end

  # The joined `MapGroup("...")` prefixes in `prefix_source`, led by the
  # prefix of the receiver variable the chain starts from; "" when none.
  private def group_chain_prefix(prefix_source : String, group_prefixes : Hash(String, String)) : String
    parts = prefix_source.scan(/MapGroup\s*\(\s*@?"([^"]+)"/).map(&.[1]?.to_s)
    return "" if parts.empty?

    # A chained `group.MapGroup("/sub").Map*(...)` registration carries the
    # accumulated prefix of the leading receiver variable (e.g. `admin` ->
    # `/admin`) which the verb-regex receiver can't see (it resolves to the
    # `)` of the chained call). Resolve and prepend it so the route keeps the
    # full `/admin/sub/...` path instead of dropping to `/sub/...`.
    if head = prefix_source.match(/\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*MapGroup\s*\(/)
      if head_prefix = group_prefixes[head[1]]?
        parts.unshift(head_prefix)
      end
    end

    join_route_parts_array(parts)
  end

  private def extract_map_group_prefixes(content : String) : Hash(String, String)
    prefixes = Hash(String, String).new
    content.split(';').each do |statement|
      next unless statement.includes?("=") && statement.includes?("MapGroup")

      left, right = statement.split("=", 2)
      variable = left.strip.split(/\s+/).last?
      next unless variable && variable.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)

      parent_prefix = ""
      if parent_match = right.match(/\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*MapGroup\s*\(/)
        parent_prefix = prefixes[parent_match[1]]? || ""
      end

      parts = right.scan(/MapGroup\s*\(\s*@?"([^"]+)"/).map(&.[1]?.to_s)
      next if parts.empty?

      prefixes[variable] = join_route_parts_array([parent_prefix] + parts)
    end
    prefixes
  end

  private def apply_group_prefix(route : String, receiver : String?, group_prefixes : Hash(String, String)) : String
    return route unless receiver
    prefix = group_prefixes[receiver]?
    return route unless prefix
    join_route_parts(prefix, route)
  end

  private def join_route_parts(*parts : String) : String
    join_route_parts_array(parts.to_a)
  end

  private def join_route_parts_array(parts : Array(String)) : String
    clean_parts = parts.compact_map do |part|
      clean = part.strip.gsub(/^\//, "").gsub(/\/$/, "")
      clean.empty? ? nil : clean
    end
    return "/" if clean_parts.empty?
    "/" + clean_parts.join("/")
  end

  # The registration statement starting at `start_column` of
  # `lines[start_index]`, up to the `;` that ends it. Depth is counted over
  # `masked_lines` so a `(` inside a route string (`"/smile-("`) can't hold
  # the statement open and swallow the registrations after it.
  #
  # `start_chars` is `{line.chars, masked.chars}` of the start line, built once
  # by a caller that extracts several statements from it.
  private def extract_map_block(lines : Array(String), masked_lines : Array(String), start_index : Int32,
                                start_column : Int32 = 0,
                                start_chars : Tuple(Array(Char), Array(Char))? = nil) : String
    io = String::Builder.new
    paren_depth = 0
    brace_depth = 0
    i = start_index

    while i < lines.size
      line = lines[i]
      masked = masked_lines[i]? || line
      from = i == start_index ? start_column : 0
      if from == 0 && !masked.includes?(';')
        paren_depth += masked.count('(') - masked.count(')')
        brace_depth += masked.count('{') - masked.count('}')
        io << line
      else
        # Char arrays index in O(1); `String#[]` is O(n) on multi-byte text.
        line_chars, masked_chars = (start_chars if i == start_index) || {line.chars, masked.chars}
        (from...masked_chars.size).each do |column|
          char = masked_chars[column]
          io << (line_chars[column]? || ' ')
          case char
          when '(' then paren_depth += 1
          when ')' then paren_depth -= 1
          when '{' then brace_depth += 1
          when '}' then brace_depth -= 1
          when ';'
            return io.to_s if paren_depth <= 0 && brace_depth <= 0
          end
        end
      end
      io << '\n'
      i += 1
    end

    io.to_s
  end

  # `request.Headers[TokenHeader]` / `[FromHeader(Name = TokenHeader)]`: a
  # key held in a string constant.
  CONST_REFERENCE_RE = /(?:Request|request)\.(?:Query|Headers|Cookies|Form)\[\s*[A-Za-z_]|\[From\w+\s*\(\s*Name\s*=\s*[A-Za-z_]/
  CONST_STRING_RE    = /\bconst\s+string\s+([A-Za-z_]\w*)\s*=\s*@?"([^"]*)"\s*;/

  # The file's `const string Name = "value";` declarations.
  private def string_consts(lines : Array(String)) : Hash(String, String)
    consts = {} of String => String
    lines.each do |line|
      line.scan(CONST_STRING_RE) { |m| consts[m[1]] = m[2] } if line.includes?("const")
    end
    consts
  end

  # `[FromHeader(Name = TokenHeader)]` with the constant's value inlined.
  private def inline_binding_name(param_def : String, consts : Hash(String, String)?) : String
    return param_def unless consts
    param_def.sub(/(\[From\w+\s*\(\s*Name\s*=\s*)([A-Za-z_]\w*)/) do |text, m|
      (value = consts[m[2]]?) ? "#{m[1]}\"#{value}\"" : text
    end
  end

  private def extract_params_from_block(block : String, consts : Hash(String, String)? = nil) : Array(Param)
    params = [] of Param
    {
      /(?:Request|request)\.Query\[\s*(?:"([^"]+)"|([A-Za-z_]\w*))\s*\]/   => "query",
      /(?:Request|request)\.Headers\[\s*(?:"([^"]+)"|([A-Za-z_]\w*))\s*\]/ => "header",
      /(?:Request|request)\.Cookies\[\s*(?:"([^"]+)"|([A-Za-z_]\w*))\s*\]/ => "cookie",
      /(?:Request|request)\.Form\[\s*(?:"([^"]+)"|([A-Za-z_]\w*))\s*\]/    => "form",
      /GetProperty\s*\(\s*"([^"]+)"\s*\)/                                  => "json",
    }.each do |regex, param_type|
      block.scan(regex) do |match|
        key = match[1]? || match[2]?.try { |name| consts.try(&.[name]?) }
        params << Param.new(key, "", param_type) if key && !key.empty?
      end
    end

    params.uniq(&.name)
  end

  private def extract_bind_params_from_file(block : String, lines : Array(String), masked_lines : Array(String)) : Array(Param)
    return [] of Param unless block.includes?("Bind(") || block.includes?("BindAsync(")

    params = [] of Param
    lines.each_with_index do |line, index|
      next unless line.includes?("Bind(") || line.includes?("BindAsync(")
      next unless line.includes?("public") || line.includes?("private") || line.includes?("protected") || line.includes?("internal") || line.includes?("static")

      _, end_idx = build_signature(lines, masked_lines, index)
      body = extract_method_block(lines, masked_lines, end_idx)
      params.concat(extract_params_from_block(body))
    end

    params.uniq(&.name)
  end

  private def extract_delegate_params(block : String, route : String, http_method : String, file : String,
                                      lines : Array(String), masked_lines : Array(String)) : Array(Param)
    lambda_params = extract_lambda_param_list(block)
    return [] of Param if lambda_params.empty?

    lambda_params = inline_binding_name(lambda_params, string_consts(lines)) if lambda_params.matches?(CONST_REFERENCE_RE)
    bound_handler_params(lambda_params, route, http_method, file, lines, masked_lines)
  end

  private def extract_lambda_param_list(block : String) : String
    arrow_index = block.index("=>")
    return "" unless arrow_index

    # Index over `Array(Char)` (O(1)) rather than `String#[](Int)`, which is
    # O(n) per access on multi-byte source and turns these backward scans
    # O(n^2) on a non-ASCII (CJK comment/string) inline lambda handler.
    chars = block.chars

    end_index = arrow_index - 1
    while end_index >= 0 && chars[end_index].ascii_whitespace?
      end_index -= 1
    end
    return "" if end_index < 0

    if chars[end_index] == ')'
      depth = 0
      index = end_index
      while index >= 0
        case chars[index]
        when ')'
          depth += 1
        when '('
          depth -= 1
          return block[(index + 1)...end_index] if depth == 0
        end
        index -= 1
      end

      return ""
    end

    start_index = end_index
    while start_index >= 0 && (chars[start_index].ascii_alphanumeric? || chars[start_index] == '_')
      start_index -= 1
    end
    block[(start_index + 1)..end_index]
  end

  private def delegate_param_to_noir_param(param_def : String, route_params : Array(String), http_method : String) : Param?
    cleaned = param_def.strip
    return if cleaned.empty?

    explicit_name = Common.explicit_binding_name(cleaned)
    param_type = Common.binding_attribute_type(cleaned)
    cleaned = cleaned.gsub(/\[[^\]]+\]\s*/, "").strip
    cleaned = cleaned.sub(/=.*/, "").strip
    cleaned = cleaned.gsub(/\b(ref|out|in|params)\b/, "").strip
    return if cleaned.empty?

    name_match = cleaned.match(/([A-Za-z_][A-Za-z0-9_]*)\s*$/)
    return unless name_match

    name = explicit_name || name_match[1]
    type_name = cleaned[0...(cleaned.size - name_match[1].size)].strip
      .gsub(/\?$/, "")
      .split(/\s+/).last? || ""
    type_name = type_name.split(".").last

    # A lambda parameter with no type annotation only compiles against the
    # `RequestDelegate` overload — `endpoints.MapGet("/headers", async context
    # => …)` — so the name is the HttpContext, never a bound request value.
    # Every such registration used to contribute a phantom `query` param.
    return if type_name.empty? && param_type.nil?

    return if service_binding?(type_name, cleaned, param_type)

    if route_params.includes?(name)
      param_type = "path"
    elsif param_type.nil?
      param_type = default_delegate_param_type(type_name, http_method)
    end

    return if param_type == "service"
    Param.new(name, "", param_type || "query")
  end

  private def service_binding?(type_name : String, full_definition : String, param_type : String?) : Bool
    return true if param_type == "service"
    return true if SERVICE_BINDING_TYPES.includes?(type_name)
    return true if full_definition.includes?("HttpContext") || full_definition.includes?("HttpRequest") || full_definition.includes?("HttpResponse")
    return true if type_name.starts_with?("ILogger")
    # DbContexts, repositories, MediatR senders, mappers and other DI
    # collaborators injected straight into the handler delegate are not
    # request-bound values.
    Common.csharp_service_type?(type_name)
  end

  private def default_delegate_param_type(type_name : String, http_method : String) : String
    return "query" if SIMPLE_BINDING_TYPES.includes?(type_name)
    # `IFormFile` / `IFormFileCollection` / `IFormCollection` bind from the
    # multipart form, never the JSON body.
    return "form" if Common::SERVICE_FORM_INPUT_TYPES.includes?(type_name)

    case http_method
    when "POST", "PUT", "PATCH"
      "json"
    else
      "query"
    end
  end

  private def build_endpoint_from_route(raw_route : String, http_method : String, file : String, line : Int32, extra_params : Array(Param) = [] of Param) : Endpoint?
    return if raw_route.empty?

    route = normalize_route(raw_route)
    params = build_path_params(route)
    extra_params.each do |param|
      params << param unless params.any? { |p| p.name == param.name && p.param_type == param.param_type }
    end
    route = prune_optional_placeholders(route, params)

    details = Details.new(PathInfo.new(file, line))
    endpoint = Endpoint.new(route, http_method, details)
    params.each { |param| endpoint.params << param }
    endpoint
  end

  private def normalize_route(route : String) : String
    normalized = route.strip
    normalized = normalized.gsub(/^\//, "").gsub(/\/+/, "/")
    normalized = "/" + normalized unless normalized.starts_with?("/")
    normalized = "/" if normalized == "//" || normalized == "/"
    normalized
  end

  private def build_path_params(route : String) : Array(Param)
    extract_route_placeholders(route).map do |name|
      Param.new(name, "", "path")
    end
  end

  private def prune_optional_placeholders(route : String, parameters : Array(Param)) : String
    param_names = parameters.map(&.name)
    result = route.dup

    route.scan(/\{([^}]+)\}/) do |match|
      raw = match[1]? || match[0]
      next unless raw

      optional = raw.ends_with?("?")
      name = Common.route_placeholder_name(raw)

      if optional && !param_names.includes?(name)
        result = result.gsub("/{#{raw}}", "")
        result = result.gsub("{#{raw}}/", "")
        result = result.gsub("{#{raw}}", "")
      elsif optional || raw.includes?('=')
        # `{id?}` -> `{id}` and `{id=5}` -> `{id}`: a default value is part of
        # the route *template*, never of the URL a client sends.
        result = result.gsub("{#{raw}}", "{#{raw.split('=').first.rstrip('?')}}")
      end
    end

    result
  end

  private def extract_route_placeholders(route : String) : Array(String)
    keys = [] of String
    route.scan(/\{([^}]+)\}/) do |match|
      raw = match[1]? || match[0]
      next unless raw

      keys << Common.route_placeholder_name(raw)
    end

    keys.uniq
  end

  # --- Method-group handler resolution -------------------------------------

  # Resolves a `MapGet("/x", HandlerMethod)` style registration to the
  # referenced method's signature + body. Returns
  # `{name, signature, body, body_start_line, skip_first_line, decl_line}`
  # or nil when the handler is a lambda (already handled) or can't be found
  # in this file. A qualified `Type.Method` resolves only when this file
  # declares `Type`, so a same-named method of another class is never taken.
  private def resolve_handler_method(block : String, lines : Array(String), masked_lines : Array(String)) : Tuple(String, String, String, Int32, Bool, Int32)?
    name = handler_method_name(block)
    return unless name
    *qualifier, method = name.split('.')
    unless qualifier.empty?
      type_re = /\b(?:class|record|struct)\s+#{Regex.escape(qualifier.last)}\b/
      return unless lines.any? { |l| l.includes?(qualifier.last) && l.matches?(type_re) }
    end
    locate_method_definition(method, lines, masked_lines).try do |sig, body, body_line, skip_first, decl_line|
      {name, sig, body, body_line, skip_first, decl_line}
    end
  end

  # Pulls the handler argument out of the `Map*(...)` call and returns it
  # as written (`GetItems`, `Handlers.GetItems`) when it's a method group (a
  # bare/qualified identifier), or nil for lambdas, string literals and
  # inline expressions.
  private def handler_method_name(block : String) : String?
    args = map_call_arguments(block)
    return if args.size < 2

    handler = args.last.strip
    return if handler.empty?
    return if handler.includes?("=>")   # lambda
    return if handler.starts_with?('"') # string literal
    return if handler.starts_with?("new")
    return unless handler.matches?(/\A@?[A-Za-z_][A-Za-z0-9_]*(?:\s*\.\s*[A-Za-z_][A-Za-z0-9_]*)*\z/)

    handler.gsub(/\s+/, "").lchop('@')
  end

  # 1-based line where an inline lambda handler (the last `Map*` argument)
  # starts, `line` being the block's first line; nil for any other handler.
  private def lambda_handler_line(block : String, line : Int32) : Int32?
    args = map_call_arguments(block)
    return if args.size < 2
    handler = args.last.strip
    return unless handler.includes?("=>")
    offset = block.rindex(handler) || return
    line + block[0...offset].count('\n')
  end

  # Top-level argument list of the first `Map*` invocation in the block,
  # split on commas while respecting nested parens/brackets/braces/generics
  # and string literals.
  private def map_call_arguments(block : String) : Array(String)
    # Find the call and its parens on the masked block so a `(` or `)`
    # inside a string argument can't unbalance them.
    masked = Noir::CSharpLexer.new(block).masked_source
    m = masked.match(MAP_CALL_RE)
    return [] of String unless m

    open = masked.index('(', m.begin)
    return [] of String unless open

    # Index over `Array(Char)` (O(1)) rather than `String#[](Int)`, which is
    # O(n) per access on multi-byte source and turns this paren-depth walk
    # O(n^2) across a large inline lambda handler with non-ASCII content.
    chars = masked.chars
    depth = 0
    i = open
    close = -1
    while i < chars.size
      case chars[i]
      when '('
        depth += 1
      when ')'
        depth -= 1
        if depth == 0
          close = i
          break
        end
      end
      i += 1
    end
    return [] of String if close < 0

    split_csharp_parameters(block[(open + 1)...close])
  end

  # Finds a method declaration by name in the file and returns its
  # signature, body block, body start line (1-based) and whether the
  # callee scanner should skip the first body line, then the declaration
  # line (1-based). Skips the registration call itself and assignment/call
  # sites.
  private def locate_method_definition(name : String, lines : Array(String), masked_lines : Array(String)) : Tuple(String, String, Int32, Bool, Int32)?
    decl = /(?:public|private|internal|protected|static|async)\b[^;={(]*\b#{Regex.escape(name)}\s*\(/

    lines.each_with_index do |line, idx|
      next unless line.includes?(name)
      next unless line.matches?(decl)
      # The `Map*("/x", Name)` line also references the handler — skip it.
      next if line.matches?(MAP_CALL_RE)

      sig, end_idx = build_signature(lines, masked_lines, idx)
      block, body_idx, skip_first = extract_callable_body(lines, masked_lines, end_idx)
      return if block.empty?
      return {sig, block, body_idx + 1, skip_first, idx + 1}
    end

    nil
  end

  # Builds params from a resolved handler's signature, reusing the delegate
  # binding rules and expanding `[AsParameters]` bundle types.
  private def handler_signature_params(signature : String, route : String, http_method : String, file : String, lines : Array(String), masked_lines : Array(String)) : Array(Param)
    list = extract_balanced_param_list(signature)
    return [] of Param unless list

    list = list.strip
    return [] of Param if list.empty?

    list = inline_binding_name(list, string_consts(lines)) if list.matches?(CONST_REFERENCE_RE)
    bound_handler_params(list, route, http_method, file, lines, masked_lines)
  end

  # Params bound from a handler's parameter list — an inline lambda's or a
  # method group's — expanding `[AsParameters]` bundle types and body DTOs
  # (`CreateOrderRequest request` is the members a client sends, not a
  # field called `request`).
  private def bound_handler_params(list : String, route : String, http_method : String, file : String, lines : Array(String), masked_lines : Array(String)) : Array(Param)
    route_params = extract_route_placeholders(route)
    params = [] of Param
    split_csharp_parameters(list).each do |pdef|
      if pdef.includes?("[AsParameters]") || pdef.includes?("[AsParameters ")
        params.concat(expand_as_parameters(pdef, file, lines, masked_lines, route_params, http_method))
      elsif param = delegate_param_to_noir_param(pdef, route_params, http_method)
        members = body_type_params(pdef, param.param_type, file, lines, masked_lines) if param.param_type.in?("json", "form")
        members ? params.concat(members) : (params << param)
      end
    end
    params.uniq(&.name)
  end

  # `[AsParameters] SomeType arg` binds each public member of `SomeType`
  # from the query/route/header — never the body. Expand to those members,
  # dropping the DI-service members (a bundle like `CatalogServices` yields
  # nothing, which is exactly right).
  private def expand_as_parameters(param_def : String, file : String, lines : Array(String), masked_lines : Array(String), route_params : Array(String), http_method : String) : Array(Param)
    cleaned = param_def.gsub(Common::ATTRIBUTE_LIST_RE, "").strip
    type_token = cleaned.split(/\s+/).first?
    return [] of Param unless type_token

    base = type_token.gsub(/<.*>/, "").split('.').last
    return [] of Param if base.empty?
    return [] of Param if Common.csharp_service_type?(base)

    params = [] of Param
    type_member_defs(base, file, lines, masked_lines).each do |member|
      param = as_parameters_member_to_param(member, route_params, http_method)
      params << param if param
    end
    params.uniq(&.name)
  end

  # Maps a single `[AsParameters]` member to a Param. Defaults to query
  # (members bind from query/route/header, never the body) and honours an
  # explicit `[FromHeader]`/`[FromQuery]`/`[FromRoute]` on the member.
  private def as_parameters_member_to_param(member_def : String, route_params : Array(String), http_method : String) : Param?
    explicit_name = Common.explicit_binding_name(member_def)
    param_type = Common.binding_attribute_type(member_def)
    cleaned = member_def.gsub(Common::ATTRIBUTE_LIST_RE, "").strip
    cleaned = cleaned.sub(/=.*/, "").strip
    cleaned = cleaned.gsub(/\b(ref|out|in|params)\b/, "").strip
    return if cleaned.empty?

    name_match = cleaned.match(/([A-Za-z_][A-Za-z0-9_]*)\s*$/)
    return unless name_match

    name = explicit_name || name_match[1]
    type_name = cleaned[0...(cleaned.size - name_match[1].size)].strip
      .gsub(/\?$/, "")
      .split(/\s+/).last? || ""
    type_name = type_name.split('.').last

    return if service_binding?(type_name, cleaned, param_type)
    return if param_type == "service"

    param_type ||= if route_params.includes?(name)
                     "path"
                   elsif Common::SERVICE_FORM_INPUT_TYPES.includes?(type_name)
                     "form"
                   else
                     "query"
                   end
    Param.new(name, "", param_type)
  end
end
