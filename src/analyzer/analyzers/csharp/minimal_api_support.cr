require "../../../miniparsers/csharp_handler_declarations"
require "../../../miniparsers/csharp_minimal_api_config"

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
  # The route capture is set only when a plain literal is the whole first
  # argument; anything else is evaluated by `route_template_value`.
  MAP_VERB_ROUTE_RE = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?Map(Get|Post|Put|Delete|Patch|Head|Options)\s*(?:<[^<>()]*>\s*)?\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?(?:@?"([^"]*)"(?=\s*[,)]))?/m
  MAP_METHODS_RE    = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?MapMethods\s*(?:<[^<>()]*>\s*)?\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?@?"([^"]*)"\s*,\s*([\s\S]+?)(?:=>|\);)/m
  MAP_CALL_RE       = /\bMap(?:Get|Post|Put|Delete|Patch|Head|Options|Methods|HealthChecks|Forwarder)?\s*(?:<[^<>()]*>\s*)?\(/
  MAP_ANY_PREFIX_RE = /\.?\s*Map(?:Get|Post|Put|Delete|Patch|Head|Options|Methods|HealthChecks|Forwarder)?\s*(?:<[^<>()]*>\s*)?\(/
  # `Map(pattern, …)` and the extensions that wrap it with no method filter:
  # `MapHealthChecks("/health")`, YARP's `MapForwarder("/x/{id}", …)`.
  MAP_ANY_METHOD_RE = /\.\s*Map(?:HealthChecks|Forwarder)?\s*\(/
  MAP_ANY_ROUTE_RE  = /(?:\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*)?Map(?:HealthChecks|Forwarder)?\s*\(\s*(?:[A-Za-z_][A-Za-z0-9_]*\s*:\s*)?(?:@?"([^"]*)"(?=\s*[,)]))?/m

  private def analyze_minimal_api_files(include_callee : Bool)
    sources = [] of Tuple(String, String)
    get_files_by_extension(".cs").each do |file|
      next if Common.csharp_test_path?(base_relative_path(file))

      content = read_file_content(file)
      # Carter modules register minimal-API routes too, but under a module
      # base path this analyzer can't see — `cs_carter` owns them.
      next if Common.carter_module_source?(content)
      sources << {file, content}
    end

    roots = Common.project_roots(get_files_by_extension(".csproj"))
    sources.group_by { |file, _| Common.project_root_for(file, roots) || configured_base_for(file) }.each_value do |project|
      @binding_config = Noir::CSharpMinimalApiConfig.new
      project.each { |_, content| @binding_config.read(content) }
      @binding_config.finish
      extension_scopes = route_group_extension_scopes(project)
      project.each do |file, content|
        next unless minimal_api_source?(content)
        analyze_minimal_api_content(file, content, include_callee, extension_scopes[file]? || [] of ExtensionScope)
      end
    end
  end

  @binding_config = Noir::CSharpMinimalApiConfig.new
  @handler_declarations = Hash(String, Noir::CSharpHandlerDeclarations).new

  record RoutePart, text : String = "", unread : Bool = false, versioned : Bool? = nil

  private def version_metadata(masked : String) : Bool?
    return false if masked.matches?(Noir::CSharpMinimalApiConfig::NEUTRAL_METADATA)
    true if masked.matches?(Noir::CSharpMinimalApiConfig::VERSION_METADATA)
  end

  # A `static … MapTodosApi(this RouteGroupBuilder group)` extension method:
  # the routes it registers on `group` take the prefix of whichever
  # `MapGroup(...)` it is called on, possibly from another file —
  #
  #   app.MapGroup("/public/todos").MapTodosApi();
  #   app.MapGroup("/private/todos").MapTodosApi();
  ROUTE_BUILDER_EXTENSION_RE = /\bstatic\s[^;{}()=]*?\b([A-Za-z_][A-Za-z0-9_]*)\s*(?:<[^<>()]*>\s*)?\(\s*this\s+(?:RouteGroupBuilder|IEndpointRouteBuilder|WebApplication)\b/

  # `{body_line_range, caller_prefixes}` of one extension method in a file.
  alias ExtensionScope = Tuple(Range(Int32, Int32), Array(RoutePart))

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
    calls = [] of Tuple(String, String, Int32, RoutePart)
    sources.each do |file, content|
      next unless content.matches?(call_re)
      lexer = Noir::CSharpLexer.new(content)
      masked = lexer.masked_source
      code = lexer.code_source
      group_scopes = group_prefix_scopes(file, lexer)
      masked.scan(call_re) do |m|
        stmt_start = (masked.rindex(/[;{}]/, m.begin) || -1) + 1
        head = code[stmt_start...m.begin]
        line = masked[0...m.begin].count('\n')
        group_prefixes = group_scopes.find(&.[0].includes?(line)).try(&.[1]) || Hash(String, RoutePart).new
        local = group_chain_prefix(head, group_prefixes, file, line - head.count('\n'))
        if local.text.empty? && !local.unread && (receiver = head.match(/([A-Za-z_][A-Za-z0-9_]*)\s*\z/))
          local = group_prefixes[receiver[1]]? || RoutePart.new
        end
        calls << {m[1], file, line, local}
      end
    end

    memo = Hash(String, Array(RoutePart)).new
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
                                        calls : Array(Tuple(String, String, Int32, RoutePart)),
                                        memo : Hash(String, Array(RoutePart)), seen : Set(String)) : Array(RoutePart)
    if cached = memo[name]?
      return cached
    end
    return [RoutePart.new] unless seen.add?(name)

    sites = calls.select { |call| call[0] == name }
    return memo[name] = [RoutePart.new] if sites.empty?

    prefixes = sites.flat_map do |_, file, line, local|
      outer = decls.find { |decl| decl[1] == file && decl[2].includes?(line) }
      outer_prefixes = outer ? extension_caller_prefixes(outer[0], decls, calls, memo, seen) : [RoutePart.new]
      outer_prefixes.map { |outer_prefix| join_route_parts(outer_prefix, local) }
    end
    memo[name] = prefixes.uniq.map { |prefix| prefix.text == "/" ? prefix.copy_with(text: "") : prefix }
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

    group_prefix_scopes(file, lexer).each do |range, group_prefixes|
      each_map_block(lines, masked_lines, range, group_prefixes, file) do |block, index, chain_prefix|
        caller_prefixes = extension_scopes.find(&.[0].includes?(index)).try(&.[1]) || [RoutePart.new]
        caller_prefixes.each do |route_prefix|
          extract_endpoints_from_map_block(block, group_prefixes, file, index + 1, lines, masked_lines,
            include_callee, route_prefix: route_prefix, chain_prefix: chain_prefix).each do |endpoint|
            @result << endpoint
          end
        end
      end
    end
  end

  alias GroupScope = Tuple(Range(Int32, Int32), Hash(String, RoutePart))

  # The `MapGroup` variables of each method or constructor body, and of the
  # top-level statements outside them, over line ranges that cover the file
  # in order. Two methods that each declare `var group` must not share it,
  # nor may a `this RouteGroupBuilder group` parameter take a sibling's local.
  # Local functions and lambdas see their enclosing member's map.
  private def group_prefix_scopes(file : String, lexer : Noir::CSharpLexer) : Array(GroupScope)
    lines = lexer.code_lines
    last = lines.size - 1
    return [GroupScope.new(0..last, Hash(String, RoutePart).new)] unless lexer.code_source.includes?("MapGroup")

    members = [] of Range(Int32, Int32)
    Noir::CSharpDeclParser.parse(lexer).types.each do |type|
      type.members.each do |member|
        members << (member.attr_line..Math.min(member.end_line, last)) if member.kind.in?(:method, :constructor)
      end
    end

    top_lines = lines.dup
    spans = [] of Tuple(Range(Int32, Int32), Hash(String, RoutePart)?)
    cursor = 0
    members.sort_by(&.begin).each do |range|
      next if range.begin < cursor
      spans << {cursor..range.begin - 1, nil} if range.begin > cursor
      range.each { |index| top_lines[index] = "" }
      spans << {range, extract_map_group_prefixes(lines[range].join('\n'), file, range.begin)}
      cursor = range.end + 1
    end
    spans << {cursor..last, nil} if cursor <= last
    top = extract_map_group_prefixes(top_lines.join('\n'), file, 0)
    spans.map { |range, prefixes| GroupScope.new(range, prefixes || top) }
  end

  # Yields `{block, line_index, chain_prefix}` for every `Map*` registration
  # on the lines in `range`, one per statement, so two registrations on one
  # line are both seen. `chain_prefix` carries the `MapGroup` prefix of a
  # chain whose `.Map*` call continues on a leading-dot line:
  #
  #   app.MapGroup("/api")
  #      .MapGet("/items", ...);
  private def each_map_block(lines : Array(String), masked_lines : Array(String), range : Range(Int32, Int32),
                             group_prefixes : Hash(String, RoutePart), file : String, &)
    chain_prefix = RoutePart.new
    range.each do |index|
      line = lines[index]
      masked = masked_lines[index]? || line
      # A comment or blank line inside a chain does not end it.
      next if masked.blank?
      continuation = masked.lstrip.starts_with?('.')
      chain_prefix = RoutePart.new unless continuation
      if route_builder_line?(line)
        starts = map_statement_starts(masked)
        start_chars = {line.chars, masked.chars} if starts.size > 1
        starts.each do |column|
          prefix = column == 0 && continuation ? chain_prefix : RoutePart.new
          yield extract_map_block(lines, masked_lines, index, column, start_chars), index, prefix
        end
      end
      next unless line.includes?("MapGroup")
      # Both sides are already normalized (`/a`, `/a/b`), so a plain append
      # joins them without re-normalizing the whole chain on every line.
      part = group_chain_prefix(line, group_prefixes, file, index)
      line_prefix = part.copy_with(text: part.text.rchop("/"))
      chain_prefix = continuation ? RoutePart.new(chain_prefix.text + line_prefix.text, chain_prefix.unread || line_prefix.unread, inherit_version(chain_prefix, line_prefix)) : line_prefix
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
                                               group_prefixes : Hash(String, RoutePart),
                                               file : String,
                                               line : Int32,
                                               file_lines : Array(String),
                                               masked_lines : Array(String),
                                               include_callee : Bool,
                                               route_prefix : RoutePart = RoutePart.new,
                                               chain_prefix : RoutePart = RoutePart.new) : Array(Endpoint)
    route, methods = extract_route_and_methods(block, group_prefixes, chain_prefix, file, line - 1)
    return [] of Endpoint unless route && methods.size > 0

    part = prepend_route_part(route_prefix, route)
    route = part.text

    consts = string_consts(file_lines) if block.matches?(CONST_REFERENCE_RE)
    extra_params = extract_params_from_block(block, consts)
    extra_params.concat(extract_bind_params_from_file(block, file_lines, masked_lines))
    binding = HandlerInputs.new(extra_params)
    handler_argument = map_call_arguments(block).last? || ""
    lambda_params = extract_lambda_param_list(handler_argument)
    bind_handler_params(binding, lambda_params, route, methods.first, file) unless lambda_params.empty?

    name = handler_method_name(handler_argument)
    handlers = name ? resolve_handler_methods(name, file, line - 1) : [] of BoundMethod
    handlers.each do |handler_file, decl|
      bind_handler_params(binding, decl.parameters, route, methods.first, handler_file)
      handler_consts = string_consts(csharp_code(handler_file).code_lines) if decl.body.matches?(CONST_REFERENCE_RE)
      extra_params.concat(extract_params_from_block(decl.body, handler_consts))
    end

    if versioned_route?(part, block)
      @binding_config.readers.each { |location, key| extra_params << Param.new(key, "", location) } if @binding_config.versioning?
      binding.unresolved = true if !@binding_config.versioning? || @binding_config.unknown_reader?
    end

    endpoints = [] of Endpoint
    methods.each do |method|
      endpoint = build_endpoint_from_route(route, method, file, line, extra_params)
      next unless endpoint

      if first = handlers.first?
        endpoint.handler = Handler.new(name.to_s, first[0], first[1].line)
        handlers.each do |handler_file, decl|
          attach_csharp_callees(endpoint, decl.body, handler_file, decl.body_line, include_callee)
        end
        endpoint.mark_resolution("handler", Endpoint::RESOLUTION_HEURISTIC) if handlers.size > 1
      else
        attach_csharp_callees(endpoint, block, file, line, include_callee)
        endpoint.mark_resolution("handler") if name
        if lambda_line = lambda_handler_line(block, line)
          endpoint.handler = Handler.new("closure", file, lambda_line)
        end
      end
      endpoint.mark_resolution("prefix") if part.unread
      endpoint.mark_resolution("params") if binding.unresolved?
      endpoints << endpoint
    end
    endpoints
  end

  private def versioned_route?(part : RoutePart, block : String) : Bool
    inherited = part.versioned == true
    return inherited unless block.includes?("ApiVersion")
    lexer = Noir::CSharpLexer.new(block)
    call = lexer.masked_source.match(MAP_CALL_RE) || return inherited
    close = lexer.matching_delimiter(call.end - 1) || return inherited
    metadata = version_metadata(lexer.masked_source[close + 1..])
    metadata.nil? ? inherited : metadata
  end

  private def extract_route_and_methods(block : String, group_prefixes : Hash(String, RoutePart), chain_prefix : RoutePart,
                                        file : String, line_index : Int32) : Tuple(RoutePart?, Array(String))
    if block.includes?("MapMethods")
      route, methods = extract_map_methods_route(block, group_prefixes, chain_prefix, file, line_index)
      return {route, methods}
    end

    inline_prefix = extract_inline_group_prefix(block, group_prefixes, chain_prefix, file, line_index)
    if match = block.match(MAP_VERB_ROUTE_RE)
      template = match[3]?.try { |literal| RoutePart.new(literal) } || route_argument_value(block, file, line_index) || return {nil, [] of String}
      receiver = match[1]?
      route = apply_group_prefix(template, receiver, group_prefixes)
      route = prepend_route_part(inline_prefix, route)
      return {route, [match[2].upcase]}
    end

    if match = block.match(MAP_ANY_ROUTE_RE)
      template = match[2]?.try { |literal| RoutePart.new(literal) } || route_argument_value(block, file, line_index) || return {nil, [] of String}
      receiver = match[1]?
      route = apply_group_prefix(template, receiver, group_prefixes)
      route = prepend_route_part(inline_prefix, route)
      return {route, ["ANY"]}
    end

    {nil, [] of String}
  end

  private def extract_map_methods_route(block : String, group_prefixes : Hash(String, RoutePart), chain_prefix : RoutePart,
                                        file : String, line_index : Int32) : Tuple(RoutePart?, Array(String))
    inline_prefix = extract_inline_group_prefix(block, group_prefixes, chain_prefix, file, line_index)

    if match = block.match(MAP_METHODS_RE)
      receiver = match[1]?
      route = apply_group_prefix(RoutePart.new(match[2]), receiver, group_prefixes)
      route = prepend_route_part(inline_prefix, route)
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

  private def extract_inline_group_prefix(block : String, group_prefixes : Hash(String, RoutePart), chain_prefix : RoutePart,
                                          file : String, line_index : Int32) : RoutePart
    map_index = block.index(MAP_ANY_PREFIX_RE)
    return RoutePart.new unless map_index

    own_prefix = group_chain_prefix(block[0...map_index], group_prefixes, file, line_index)
    return prepend_route_part(chain_prefix, own_prefix) if chain_prefix.text.empty?
    return RoutePart.new(chain_prefix.text, chain_prefix.unread || own_prefix.unread, inherit_version(chain_prefix, own_prefix)) if own_prefix.text.empty?
    join_route_parts(chain_prefix, own_prefix)
  end

  # The joined `MapGroup("...")` prefixes in `prefix_source`, led by the
  # prefix of the receiver variable the chain starts from; "" when none.
  private def group_chain_prefix(prefix_source : String, group_prefixes : Hash(String, RoutePart),
                                 file : String, line_index : Int32) : RoutePart
    parts = map_group_values(prefix_source, file, line_index)
    unread = parts.any?(&.unread)
    parts.reject! { |part| part.text.empty? && part.versioned.nil? }
    return RoutePart.new("", unread) if parts.empty?

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

    joined = join_route_parts_array(parts)
    joined.copy_with(unread: unread || joined.unread)
  end

  # `first_line` is the line index `content` starts at in `file`.
  private def extract_map_group_prefixes(content : String, file : String, first_line : Int32) : Hash(String, RoutePart)
    prefixes = Hash(String, RoutePart).new
    line = first_line
    content.split(';').each do |statement|
      statement_line = line
      line += statement.count('\n')
      if statement.includes?("ApiVersion") && (call = statement.match(/\A\s*(\w+)\s*\.\s*(?:Has(?:Deprecated)?ApiVersion|WithApiVersionSet|IsApiVersionNeutral)\s*\(/))
        if group = prefixes[call[1]]?
          prefixes[call[1]] = group.copy_with(versioned: version_metadata(Noir::CSharpLexer.new(statement).masked_source))
        end
      end
      next unless statement.includes?("=") && statement.includes?("MapGroup")

      left, right = statement.split("=", 2)
      variable = left.strip.split(/\s+/).last?
      next unless variable && variable.matches?(/^[A-Za-z_][A-Za-z0-9_]*$/)

      parent_prefix = RoutePart.new
      if parent_match = right.match(/\b([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*MapGroup\s*\(/)
        parent_prefix = prefixes[parent_match[1]]? || RoutePart.new
      end

      parts = map_group_values(right, file, statement_line + left.count('\n'))
      if parts.all? { |part| part.text.empty? && part.versioned.nil? }
        # No literal was collected, so the old reader kept the prior text.
        if parts.any?(&.unread)
          prefixes[variable] = RoutePart.new(prefixes[variable]?.try(&.text) || "", true)
        end
        next
      end

      prefixes[variable] = join_route_parts_array([parent_prefix] + parts)
    end
    prefixes
  end

  MAP_GROUP_CALL_RE      = /\bMapGroup\s*\(/
  PLAIN_TEMPLATE_RE      = /\A@?"([^"]*)"\z/
  LEADING_LITERAL_RE     = /\A@?"([^"]*)"/
  NAMED_ARGUMENT_HEAD_RE = /\A[A-Za-z_]\w*\s*:(?!:)\s*/

  # The non-empty template of each `MapGroup(...)` call in `text`, in order;
  # `line_index` is the line `text` starts at in `file`.
  private def map_group_values(text : String, file : String, line_index : Int32) : Array(RoutePart)
    values = [] of RoutePart
    return values unless text.includes?("MapGroup")
    lexer = Noir::CSharpLexer.new(text)
    lexer.masked_source.scan(MAP_GROUP_CALL_RE) do |m|
      open = m.end(0) - 1
      close = lexer.matching_delimiter(open) || next
      arg = split_csharp_parameters(text[open + 1...close]).first? || next
      value = route_template_value(arg, file, line_index + text[0, open].count('\n'))
      part = value || RoutePart.new("", true)
      values << part.copy_with(versioned: version_metadata(lexer.masked_source[close + 1..]))
    end
    values
  end

  # The first argument of the block's `Map*` call, evaluated.
  private def route_argument_value(block : String, file : String, line_index : Int32) : RoutePart?
    map_call_arguments(block).first?.try { |arg| route_template_value(arg, file, line_index) }
  end

  # A route or group template argument: a plain literal as written, else the
  # value `csharp_string_value` reads for it at line `line_index` of `file`
  # (a const, a local, `Type.Member`, an interpolation), else the leading
  # literal of an expression it cannot read (`"/a" + suffix`).
  private def route_template_value(arg : String, file : String, line_index : Int32) : RoutePart?
    arg = arg.strip.sub(NAMED_ARGUMENT_HEAD_RE, "")
    if m = arg.match(PLAIN_TEMPLATE_RE)
      return RoutePart.new(m[1])
    end
    before = csharp_code(file).code_lines[0, line_index].join('\n')
    if value = csharp_string_value(arg, file, before)
      return RoutePart.new(value)
    end
    arg.match(LEADING_LITERAL_RE).try { |leading| RoutePart.new(leading[1], true) }
  end

  private def apply_group_prefix(route : RoutePart, receiver : String?, group_prefixes : Hash(String, RoutePart)) : RoutePart
    return route unless receiver
    prefix = group_prefixes[receiver]?
    return route unless prefix
    prepend_route_part(prefix, route)
  end

  private def prepend_route_part(prefix : RoutePart, route : RoutePart) : RoutePart
    return route.copy_with(unread: route.unread || prefix.unread, versioned: inherit_version(prefix, route)) if prefix.text.empty?
    join_route_parts(prefix, route)
  end

  private def inherit_version(prefix : RoutePart, part : RoutePart) : Bool?
    part.versioned.nil? ? prefix.versioned : part.versioned
  end

  private def join_route_parts(*parts : RoutePart) : RoutePart
    join_route_parts_array(parts.to_a)
  end

  private def join_route_parts_array(parts : Array(RoutePart)) : RoutePart
    clean_parts = parts.compact_map do |part|
      clean = part.text.strip.gsub(/^\//, "").gsub(/\/$/, "")
      clean.empty? ? nil : clean
    end
    RoutePart.new("/" + clean_parts.join("/"), parts.any?(&.unread), parts.reverse_each.find { |part| !part.versioned.nil? }.try(&.versioned))
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

    params.uniq { |param| {param.name, param.param_type} }
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

    params.uniq { |param| {param.name, param.param_type} }
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
    # `MapGet("", …)` maps the group prefix itself, or `/` outside a group.
    raw_route = "/" if raw_route.empty?

    route = Noir::URLPath.normalize(raw_route.strip.gsub(/^\//, ""), collapse: true)
    params = Noir::URLPath.template_names(route).map { |name| Param.new(name, "", "path") }
    extra_params.each do |param|
      params << param unless params.any? { |p| p.name == param.name && p.param_type == param.param_type }
    end
    route = Noir::URLPath.bind_optional_slots(route, params.map(&.name))

    details = Details.new(PathInfo.new(file, line))
    endpoint = Endpoint.new(route, http_method, details)
    params.each { |param| endpoint.params << param }
    endpoint
  end

  # --- Method-group handler resolution -------------------------------------

  alias BoundMethod = Tuple(String, Noir::CSharpHandlerDeclaration)

  private def declarations(file : String)
    @handler_declarations[file] ||= Noir::CSharpHandlerDeclarations.new(csharp_code(file))
  end

  # A bare reference is a local function, a member of the enclosing
  # (possibly partial) type, or a statically imported member.
  private def resolve_handler_methods(name : String, file : String, line : Int32) : Array(BoundMethod)
    parts = name.split('.')
    method = parts.pop
    if parts.empty?
      if local = declarations(file).local(method, line)
        return [{file, local}]
      end
      if owner = declarations(file).unit.type_at(line)
        matches = type_methods(owner.name, method, file)
        return matches unless matches.empty?
      end
      return csharp_code(file).masked_source.scan(/\busing\s+static\s+([\w.]+)\s*;/).flat_map do |m|
        type_methods(m[1], method, file)
      end
    end
    type_methods(parts.join('.'), method, file)
  end

  private def type_methods(type : String, method : String, file : String, binding_method : Bool = false) : Array(BoundMethod)
    result = [] of BoundMethod
    each_handler_type(type, file) do |candidate, decl|
      decl.methods.each do |member|
        next unless member.name == method
        next if binding_method && !binding_method?(member)
        if handler = declarations(candidate).method(member)
          result << {candidate, handler}
        end
      end
    end
    result
  end

  private def each_handler_type(type : String, file : String, &)
    short = type.split('.').last
    candidates = csharp_type_files[short]? || return
    path, namespace = resolve_type_file(type, file) || return
    root = Common.project_root_for(file, @csharp_project_roots) || configured_base_for(file)
    candidates.each do |candidate|
      next unless (Common.project_root_for(candidate, @csharp_project_roots) || configured_base_for(candidate)) == root
      declarations(candidate).unit.types.each do |decl|
        next unless decl.name == short && (namespace.nil? || decl.namespace == namespace)
        next unless path == candidate || decl.partial?
        full_name = "#{decl.namespace}.#{qualified_type(decl)}"
        yield candidate, decl if full_name.ends_with?(".#{type}") || full_name == type
      end
    end
  end

  private def binding_method?(member : Noir::CSharpDecl::Member) : Bool
    return false unless member.public? && member.static?
    first = member.params.first?.try(&.type.split('.').last)
    if member.name == "BindAsync"
      first == "HttpContext" && member.return_type.includes?("ValueTask")
    else
      first.in?("string", "String", "string?", "String?") && member.params.last?.try(&.modifiers.includes?("out")) == true && member.return_type.in?("bool", "Boolean", "System.Boolean")
    end
  end

  private def qualified_type(decl : Noir::CSharpDecl::TypeDecl) : String
    decl.outer.try { |outer| "#{qualified_type(outer)}.#{decl.name}" } || decl.name
  end

  # Pulls the handler argument out of the `Map*(...)` call and returns it
  # as written (`GetItems`, `Handlers.GetItems`) when it's a method group (a
  # bare/qualified identifier), or nil for lambdas, string literals and
  # inline expressions.
  private def handler_method_name(argument : String) : String?
    handler = argument.strip.sub(NAMED_ARGUMENT_HEAD_RE, "")
    return if handler.empty?
    return if handler.includes?("=>")   # lambda
    return if handler.starts_with?('"') # string literal
    return if handler.starts_with?("new ")
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

  class HandlerInputs
    getter params : Array(Param)

    def initialize(@params)
    end

    property? unresolved = false
  end

  # Params bound from a handler's parameter list — an inline lambda's or a
  # method group's — expanding `[AsParameters]` bundle types and body DTOs
  # (`CreateOrderRequest request` is the members a client sends, not a
  # field called `request`).
  private def bind_handler_params(binding : HandlerInputs, list : String, route : String, method : String, file : String)
    route_params = Noir::URLPath.template_names(route)
    split_csharp_parameters(list).each do |definition|
      bind_argument(binding, definition, route_params, method, file)
    end
  end

  BIND_ATTRIBUTE = /\[(?:(?:property|param)\s*:\s*)?(?:[\w.]+\.)?(AsParameters|From(?:Query|Route|Header|Body|Form|Services|KeyedServices))(?:Attribute)?\b/

  private def expand_bundle(binding : HandlerInputs, type : String, file : String, route_params : Array(String), method : String)
    expand_bundle(binding, type, file, route_params, method, Set(String).new, Set(String).new)
  end

  private def expand_bundle(binding : HandlerInputs, type : String, file : String, route_params : Array(String), method : String,
                            seen : Set(String), hidden : Set(String))
    return unless seen.add?(type)
    found = false
    bases = [] of Tuple(String, String)
    each_handler_type(type, file) do |path, decl|
      found = true
      ctors = decl.constructors.select(&.public?)
      ctor = decl.params || (ctors.first.params if ctors.size == 1)
      if decl.kind == "record" && (positional = decl.params)
        positional.each do |param|
          bind_argument(binding, param.text, route_params, method, path, member: true) if hidden.add?(param.name)
        end
      end
      decl.members.each do |prop|
        next if prop.static?
        next unless prop.kind == :property && prop.public? && hidden.add?(prop.name)
        property_type = prop.header.rchop(prop.name).strip
        prop.modifiers.each { |modifier| property_type = property_type.lchop(modifier).lstrip }
        arg = ctor.try(&.find { |param| param.name.compare(prop.name, case_insensitive: true) == 0 && param.type == property_type })
        next unless arg || prop.accessors.try(&.matches?(Common::PUBLIC_SETTER_RE))
        attrs = (arg.try(&.attributes) || [] of Noir::CSharpDecl::Attribute) + prop.attributes
        definition = attrs.join(" ") { |attr| "[#{attr.text}]" } + " #{property_type} #{prop.name}"
        bind_argument(binding, definition, route_params, method, path, member: true)
      end
      if base = decl.bases.first?
        bases << {base, path}
      end
    end
    binding.unresolved = true unless found
    bases.each { |base, path| expand_bundle(binding, base, path, route_params, method, seen, hidden) }
  end

  private def bind_argument(binding : HandlerInputs, definition : String, route_params : Array(String), method : String, file : String, member : Bool = false)
    lexer = csharp_code(file)
    definition = definition.gsub(BIND_ATTRIBUTE) { |_, match| "[#{match[1]}" }
    if definition.matches?(CONST_REFERENCE_RE)
      definition = inline_binding_name(definition, string_consts(lexer.code_lines))
      binding.unresolved = true if definition.matches?(CONST_REFERENCE_RE)
    end
    cleaned = definition.gsub(Common::ATTRIBUTE_LIST_RE, "").sub(/=.*/m, "").strip
    type = cleaned.sub(/\s*[A-Za-z_]\w*\z/, "").strip.rchop('?')
    if definition.includes?("[AsParameters]")
      if member
        binding.unresolved = true
      else
        expand_bundle(binding, type, file, route_params, method)
      end
      return
    end

    name = Common.explicit_binding_name(definition) || Common.member_name(cleaned)
    return if name.empty? || type.empty?
    source = Common.binding_attribute_type(definition)
    return if source == "service"

    if source.nil?
      key = Noir::CSharpDecl.simple_name(type)
      slot = route_params.find { |part| part.compare(name, case_insensitive: true) == 0 }
      # A custom binder takes precedence over inferred DI and body binding.
      if csharp_type_files.has_key?(key)
        binders = type_methods(type, "BindAsync", file, binding_method: true)
        unless binders.empty?
          opaque = false
          binders.each do |path, decl|
            keys = extract_params_from_block(decl.body, string_consts(csharp_code(path).code_lines))
            binding.params.concat(keys)
            opaque = true if keys.empty?
          end
          return unless opaque
          # Preserve the normal binding candidate when the custom binder
          # delegates the read or uses a key we cannot recover.
          binding.unresolved = true
        end
        scalar = !type_methods(type, "TryParse", file, binding_method: true).empty?
      end
      unless scalar || SIMPLE_BINDING_TYPES.includes?(key)
        return if @binding_config.services.includes?(type) || Common.csharp_service_type?(key) || SERVICE_BINDING_TYPES.includes?(key)
      end
      name = slot if slot
      source = if slot
                 "path"
               elsif scalar
                 "query"
               else
                 default_delegate_param_type(key, method)
               end
    end
    members = body_type_params(definition, source, file, lexer.code_lines, lexer.masked_lines) if source.in?("json", "form")
    members ? binding.params.concat(members) : (binding.params << Param.new(name, "", source))
  end
end
