require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./go_callee_extractor"
require "./go_struct_fields"
require "../utils/c_comments"

module Noir::GoRequestParamExtractor
  extend self

  MAX_HELPER_DEPTH = 3

  # Lookups across packages for the walk: a helper called through an
  # imported package (`request.QueryBoolParam(r, "force", false)`), the
  # string constants a package declares (`paramTagsAdd = "a"`), and the
  # struct a decoded body fills.
  class Resolver
    getter bodies : Noir::GoCalleeExtractor::LazyPackageBodies
    getter structs : Noir::GoStructFields::Index

    @files_by_dir = Hash(String, Array(String)).new
    @aliases = Hash(String, Hash(String, String)).new
    @constants = Hash(String, Hash(String, String)).new
    @mutex = Mutex.new

    def initialize(@bodies, @file_contents : Hash(String, String), @import_dirs : Hash(String, String))
      @structs = Noir::GoStructFields::Index.new(@file_contents, @import_dirs)
      @file_contents.each_key do |path|
        (@files_by_dir[File.dirname(path)] ||= [] of String) << path unless path.ends_with?("_test.go")
      end
    end

    # The function `qualifier.name` names from `file` when `qualifier` is
    # an import of a scanned package.
    def imported_function(file : String, qualifier : String, name : String) : Noir::GoCalleeExtractor::FunctionBody?
      import_path = aliases(file)[qualifier]? || return
      dir = @import_dirs[import_path]? || return
      @bodies.functions_for(dir)[name]?
    end

    private def aliases(file : String) : Hash(String, String)
      @mutex.synchronize do
        @aliases[file] ||= @file_contents[file]?.try { |c| Noir::GoCalleeExtractor.extract_import_aliases(c) } || Hash(String, String).new
      end
    end

    CONST_LINE = /\A(?:const\s+)?([A-Za-z_]\w*)(?:\s+string)?\s*=\s*"((?:[^"\\]|\\.)*)"\s*(?:\/\/.*)?\z/

    # The string constants declared in the package at `dir`, by name.
    def constants(dir : String) : Hash(String, String)
      @mutex.synchronize do
        @constants[dir] ||= begin
          table = Hash(String, String).new
          @files_by_dir[dir]?.try &.each do |file|
            content = @file_contents[file]? || next
            next unless content.includes?("const")
            in_block = false
            content.each_line do |raw|
              line = raw.strip
              if line.starts_with?("const (")
                in_block = true
              elsif in_block && line.starts_with?(')')
                in_block = false
              elsif (in_block || line.starts_with?("const ")) && (m = line.match(CONST_LINE))
                table.put_if_absent(m[1]) { m[2] }
              end
            end
          end
          table
        end
      end
    end
  end

  # What a body is read with: the file it is declared in, its lines (for a
  # decode target's declaration) and the names that stand for strings in
  # it (package constants, and a helper's parameters bound to the literal
  # its caller passes).
  # `requests` names the body's `*http.Request` parameters, when known: a
  # header read off anything else (`resp.Header.Get(...)`) is not a request
  # input.
  # `queries` names the locals holding the parsed query (`values :=
  # r.URL.Query()`).
  record Context, resolver : Resolver?, file : String?, lines : Array(String), bindings : Hash(String, String),
    requests : Set(String)? = nil, queries : Set(String) = Set(String).new

  QUERY_ALIAS = /([A-Za-z_]\w*)\s*:?=\s*\w+\s*\.\s*URL\s*\.\s*Query\s*\(\s*\)/

  LOCAL_NAMES = /(?:\A|[\n;{(]|\bvar)\s*([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:=|\bvar\s+([A-Za-z_]\w*)|\bfor\s+([A-Za-z_]\w*(?:\s*,\s*[A-Za-z_]\w*)*)\s*:?=\s*range\b/

  # `constants` minus the names `source` declares itself (a parameter, a
  # `:=` or `var` local, a range variable): those shadow the package
  # constant.
  private def unshadowed(constants : Hash(String, String), source : String) : Hash(String, String)
    return constants if constants.empty?
    locals = Set(String).new
    source.scan(LOCAL_NAMES) do |m|
      (m[1]? || m[2]? || m[3]? || "").split(',').each { |name| locals << name.strip }
    end
    source.scan(/\bfunc\b[^{]*/) do |head|
      head[0].scan(/[(,]\s*([A-Za-z_]\w*)(?=\s*(?:,\s*[A-Za-z_]\w*\s*)*[\s*\[\]\w.]+[,)])/) { |m| locals << m[1] }
    end
    locals.empty? ? constants : constants.reject { |name, _| locals.includes?(name) }
  end

  REQUEST_PARAM = /([A-Za-z_]\w*)\s+\*\s*http\.Request\b/

  # The `*http.Request` parameters of the function whose source starts
  # `source`; nil when it takes none.
  private def request_params(source : String) : Set(String)?
    list = source.match(HELPER_PARAMS).try(&.[1]) || return
    names = list.scan(REQUEST_PARAM).map(&.[1]).to_set
    names.empty? ? nil : names
  end

  # A stdlib request-header read, whatever the request is called: `r` /
  # `req`, gin's `c.Request`, echo's `c.Request()`. `Header.Get("X")`,
  # `Header.Values("X")` and `Header["X"]`; not a `Header["X"] = v` write,
  # nor `w.Header().Get` (the response's own headers).
  HEADER_READ_RE = /\.Header\s*(?:\.\s*(?:Get|Values)\s*\(\s*["`]([^"`]+)["`]|\[\s*["`]([^"`]+)["`]\s*\](?!\s*=[^=]))/

  # Every header `text` reads, as `header` params. Shared by the Go
  # adapters whose handlers see a `*http.Request`.
  def header_params(text : String) : Array(Param)
    text.scan(HEADER_READ_RE).map { |m| Param.new(m[1]? || m[2], "", "header") }
  end

  # A read off the parsed query string: stdlib `URL.Query()` or echo's
  # `QueryParams()` (both `url.Values`), by `.Get("x")` or `["x"]`.
  QUERY_READ_RE = /\.(?:URL\s*\.\s*Query|QueryParams)\s*\(\s*\)\s*(?:\.\s*Get\s*\(\s*["`]([^"`]+)["`]|\[\s*["`]([^"`]+)["`]\s*\])/

  def query_params(text : String) : Array(Param)
    text.scan(QUERY_READ_RE).map { |m| Param.new(m[1]? || m[2], "", "query") }
  end

  # Function and method tables restricted to `dirs`, behind the `func ` /
  # `func (` per-file gates. A directory is parsed only when a route file
  # in it asks for its table. See `Noir::GoCalleeExtractor::LazyPackageBodies`.
  def lazy_package_bodies_for_dirs(file_contents : Hash(String, String),
                                   dirs : Set(String)) : Noir::GoCalleeExtractor::LazyPackageBodies
    Noir::GoCalleeExtractor::LazyPackageBodies.new(file_contents, function_gate: "func ", method_gate: "func (", only_dirs: dirs)
  end

  def function_bodies_for_directory(package_bodies : Noir::GoCalleeExtractor::LazyPackageBodies,
                                    dir : String) : Hash(String, Noir::GoCalleeExtractor::FunctionBody)
    package_bodies.functions_for(dir)
  end

  def method_bodies_for_directory(package_bodies : Noir::GoCalleeExtractor::LazyPackageBodies,
                                  dir : String) : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))
    package_bodies.methods_for(dir)
  end

  # The params the handler definition `fn` reads (and the helpers it calls,
  # through `resolver`), for a route answering `http_method`.
  def params_for_body(fn : Noir::GoCalleeExtractor::FunctionBody, http_method : String, resolver : Resolver) : Array(Param)
    dir = File.dirname(fn.file_path)
    params = [] of Param
    append_function_params(fn, http_method, resolver.bodies.functions_for(dir), resolver.bodies.methods_for(dir),
      Hash(String, Array(Param)).new, Set(String).new, params, 0, resolver, Hash(String, String).new)
    params
  end

  def params_for_routes(source : String,
                        route_rows : Set(Int32),
                        route_methods : Hash(Int32, String),
                        external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                        external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                        resolver : Resolver? = nil,
                        path : String? = nil) : Hash(Int32, Array(Param))
    by_route = Hash(Int32, Array(Param)).new
    return by_route if route_rows.empty?
    bindings = path && resolver ? unshadowed(resolver.constants(File.dirname(path)), source) : Hash(String, String).new
    ctx = Context.new(resolver, path, source.lines, bindings)

    cache = Hash(String, Array(Param)).new
    Noir::TreeSitter.parse_go(source) do |root|
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        row = Noir::TreeSitter.node_start_row(node)
        next unless route_rows.includes?(row)

        http_method = route_methods[row]? || ""
        params = [] of Param
        find_handler_args(node).each do |handler_arg|
          collect_params_for_handler_arg(
            unwrap_handler_arg(handler_arg, source),
            source,
            http_method,
            external_functions,
            external_methods,
            cache,
            Set(String).new,
            params,
            ctx
          )
        end
        by_route[row] = dedupe_params(params) unless params.empty?
      end
    end

    by_route
  end

  private def collect_params_for_handler_arg(handler_arg : LibTreeSitter::TSNode,
                                             source : String,
                                             http_method : String,
                                             external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                             external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                             cache : Hash(String, Array(Param)),
                                             visiting : Set(String),
                                             sink : Array(Param),
                                             ctx : Context)
    case Noir::TreeSitter.node_type(handler_arg)
    when "func_literal"
      if body = Noir::TreeSitter.field(handler_arg, "body")
        collect_params_in_body(body, source, http_method, external_functions, external_methods, cache, visiting, sink, 0, ctx)
      end
    when "identifier"
      name = Noir::TreeSitter.node_text(handler_arg, source)
      if fn = external_functions[name]?
        append_function_params(fn, http_method, external_functions, external_methods, cache, visiting, sink, 0, ctx.resolver, Hash(String, String).new)
      end
    when "selector_expression"
      append_selector_handler_params(handler_arg, source, http_method, external_functions, external_methods, cache, visiting, sink, ctx)
    when "call_expression"
      if candidate = fallback_handler_arg_from_call(handler_arg, source, external_functions, external_methods)
        collect_params_for_handler_arg(
          unwrap_handler_arg(candidate, source),
          source,
          http_method,
          external_functions,
          external_methods,
          cache,
          visiting,
          sink,
          ctx
        )
      end
    end
  end

  private def append_selector_handler_params(handler_arg : LibTreeSitter::TSNode,
                                             source : String,
                                             http_method : String,
                                             external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                             external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                             cache : Hash(String, Array(Param)),
                                             visiting : Set(String),
                                             sink : Array(Param),
                                             ctx : Context)
    field = Noir::TreeSitter.field(handler_arg, "field")
    return unless field

    method_name = Noir::TreeSitter.node_text(field, source)
    if (methods = external_methods[method_name]?) && methods.size == 1
      append_function_params(methods.first, http_method, external_functions, external_methods, cache, visiting, sink, 0, ctx.resolver, Hash(String, String).new)
    end
  end

  private def append_function_params(fn : Noir::GoCalleeExtractor::FunctionBody,
                                     http_method : String,
                                     external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                     external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                     cache : Hash(String, Array(Param)),
                                     visiting : Set(String),
                                     sink : Array(Param),
                                     depth : Int32,
                                     resolver : Resolver? = nil,
                                     arg_bindings : Hash(String, String) = Hash(String, String).new)
    key = "#{fn.file_path}:#{fn.start_row}:#{http_method}:#{arg_bindings.to_a.sort!.join(',')}"
    if cached = cache[key]?
      cached.each { |param| push_param(sink, param) }
      return
    end

    visit_key = "#{fn.file_path}:#{fn.start_row}"
    return if visiting.includes?(visit_key)
    visiting << visit_key

    params = [] of Param
    dir = File.dirname(fn.file_path)
    if resolver
      # The body's own package decides what its helper calls mean.
      external_functions = resolver.bodies.functions_for(dir)
      external_methods = resolver.bodies.methods_for(dir)
      bindings = unshadowed(resolver.constants(dir), fn.source).merge(arg_bindings)
    else
      bindings = arg_bindings
    end
    ctx = Context.new(resolver, fn.file_path, fn.source.lines, bindings, request_params(fn.source),
      fn.source.scan(QUERY_ALIAS).map(&.[1]).to_set)
    wrapped = "package _noir_params_wrap\n#{fn.source}\n"
    Noir::TreeSitter.parse_go(wrapped) do |root|
      Noir::TreeSitter.each_named_child(root) do |child|
        ty = Noir::TreeSitter.node_type(child)
        next unless ty == "function_declaration" || ty == "method_declaration"
        if body = Noir::TreeSitter.field(child, "body")
          collect_params_in_body(body, wrapped, http_method, external_functions, external_methods, cache, visiting, params, depth, ctx)
          break
        end
      end
    end

    visiting.delete(visit_key)
    cache[key] = dedupe_params(params)
    cache[key].each { |param| push_param(sink, param) }
  end

  private def collect_params_in_body(body : LibTreeSitter::TSNode,
                                     source : String,
                                     http_method : String,
                                     external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                     external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                     cache : Hash(String, Array(Param)),
                                     visiting : Set(String),
                                     sink : Array(Param),
                                     depth : Int32,
                                     ctx : Context)
    Noir::TreeSitter.walk(body) do |node|
      type = Noir::TreeSitter.node_type(node)
      # `items := r.Form["i"]` reads the form outside any call.
      if type == "index_expression"
        extract_params_from_call(node, source, http_method, ctx).each { |param| push_param(sink, param) }
      end
      if type == "for_statement"
        each_range_literal(node, source, ctx) do |loop_body, loop_ctx|
          collect_params_in_body(loop_body, source, http_method, external_functions, external_methods, cache, visiting, sink, depth, loop_ctx)
        end
      end
      next unless type == "call_expression"

      extract_params_from_call(node, source, http_method, ctx).each do |param|
        push_param(sink, param)
      end

      imported = depth < MAX_HELPER_DEPTH ? imported_helper_for_call(node, source, ctx) : nil
      if imported
        # Read the helper's definition, with its parameters bound to the
        # literals passed here; its name decides only when that reads
        # nothing off the request.
        found = [] of Param
        append_function_params(imported, http_method, external_functions, external_methods, cache, visiting, found, depth + 1,
          ctx.resolver, helper_bindings(imported, node, source, ctx))
        found = named_helper_params(node, source, http_method) if found.empty?
        found.each { |param| push_param(sink, param) }
        next
      end
      named_helper_params(node, source, http_method).each { |param| push_param(sink, param) }

      next if depth >= MAX_HELPER_DEPTH
      if fn = helper_function_body_for_call(node, source, external_functions, external_methods)
        append_function_params(fn, http_method, external_functions, external_methods, cache, visiting, sink, depth + 1,
          ctx.resolver, helper_bindings(fn, node, source, ctx))
      end
    end
  end

  STRING_LIST = /\A\[(?:\.\.\.)?\]string\s*\{((?:\s*"[^"]*"\s*,?)*)\s*\}\z/m

  # A loop over a list of string literals (`for _, name := range
  # [...]string{"Range", "Accept"} { r.Header.Get(name) }`, the list inline
  # or bound to a local of the body): yields the loop body once per literal,
  # with the loop variable bound to it.
  private def each_range_literal(node : LibTreeSitter::TSNode, source : String, ctx : Context, &)
    range = nil.as(LibTreeSitter::TSNode?)
    Noir::TreeSitter.each_named_child(node) { |child| range = child if Noir::TreeSitter.node_type(child) == "range_clause" }
    range = range || return
    left = Noir::TreeSitter.field(range, "left") || return
    right = Noir::TreeSitter.field(range, "right") || return
    loop_body = Noir::TreeSitter.field(node, "body") || return
    names = Noir::TreeSitter.node_text(left, source).split(',').map(&.strip)
    return unless names.size == 2 && names[1].matches?(/\A[A-Za-z_]\w*\z/)
    list = Noir::TreeSitter.node_text(right, source).strip
    if list.matches?(/\A[A-Za-z_]\w*\z/)
      decl = ctx.lines.join("\n").match(/(?<![\w.])#{Regex.escape(list)}\s*:?=\s*(\[(?:\.\.\.)?\]string\s*\{[^}]*\})/) || return
      list = decl[1]
    end
    items = list.match(STRING_LIST) || return
    items[1].scan(/"([^"]*)"/).each do |item|
      bindings = ctx.bindings.dup
      bindings[names[1]] = item[1]
      yield loop_body, ctx.copy_with(bindings: bindings)
    end
  end

  # The helper an imported package's function call names (`request.
  # RouteInt64Param(r, "id")`), when the package is in the scan.
  private def imported_helper_for_call(call : LibTreeSitter::TSNode, source : String, ctx : Context) : Noir::GoCalleeExtractor::FunctionBody?
    resolver = ctx.resolver || return
    file = ctx.file || return
    function = Noir::TreeSitter.field(call, "function") || return
    return unless Noir::TreeSitter.node_type(function) == "selector_expression"
    operand = Noir::TreeSitter.field(function, "operand") || return
    field = Noir::TreeSitter.field(function, "field") || return
    return unless Noir::TreeSitter.node_type(operand) == "identifier"
    fn = resolver.imported_function(file, Noir::TreeSitter.node_text(operand, source), Noir::TreeSitter.node_text(field, source)) || return
    # A response writer of another package (`response.JSON(w, r, v)`) reads
    # the request only to negotiate the reply.
    # A helper that is not handed the request (an outbound client, `client.
    # Fetch(ctx, url)`) reads none of it.
    params = fn.source.match(HELPER_PARAMS).try(&.[1]) || return
    fn if params.matches?(REQUEST_PARAM) && !params.includes?("http.ResponseWriter")
  end

  HELPER_PARAMS = /\Afunc\s*(?:\([^)]*\)\s*)?\w+\s*(?:\[.*?\]\s*)?\(([^)]*)\)/

  # The helper's parameters bound to the string each argument of `call`
  # stands for: a literal, or a name bound in the caller.
  private def helper_bindings(fn : Noir::GoCalleeExtractor::FunctionBody, call : LibTreeSitter::TSNode, source : String, ctx : Context) : Hash(String, String)
    bindings = Hash(String, String).new
    list = fn.source.match(HELPER_PARAMS).try(&.[1]) || return bindings
    # `param, defaultValue string` names two parameters of one type.
    names = list.split(',').map { |part| part.strip.split(/\s+/).first? || "" }
    args = Noir::TreeSitter.field(call, "arguments") || return bindings
    index = 0
    Noir::TreeSitter.each_named_arg(args) do |arg|
      name = names[index]?
      index += 1
      next unless name && name.matches?(/\A[A-Za-z_]\w*\z/)
      value = if string_literal_node?(arg)
                decode_string_literal(arg, source)
              elsif Noir::TreeSitter.node_type(arg) == "identifier"
                ctx.bindings[Noir::TreeSitter.node_text(arg, source)]?
              end
      bindings[name] = value if value
    end
    bindings
  end

  # `json.NewDecoder(r.Body).Decode(&req)`, under any alias of the package.
  JSON_DECODE   = /\b\w*json\w*\.NewDecoder\([^)]*\.Body\)\s*\.\s*Decode/
  DECODE_TARGET = /\.Decode\s*\(\s*&\s*([A-Za-z_]\w*)\s*\)/
  BOUND_NAME    = /(?<![\w."`])([A-Za-z_]\w*)(?![\w"`(])/

  private def extract_params_from_call(call : LibTreeSitter::TSNode,
                                       source : String,
                                       http_method : String,
                                       ctx : Context? = nil) : Array(Param)
    params = [] of Param
    # Comments blanked so `Get(/* c */ "q")` still matches the regexes below.
    call_text = Noir::CComments.strip(Noir::TreeSitter.node_text(call, source), raw_quotes: "`")
    # A name bound to a string reads as that string (`r.Form.Get(paramID)`).
    if ctx && !ctx.bindings.empty?
      bindings = ctx.bindings
      call_text = call_text.gsub(BOUND_NAME) { |name| (value = bindings[name]?) ? %("#{value}") : name }
    end

    if call_text.matches?(JSON_DECODE)
      fields = decoded_fields(call_text, ctx)
      fields ? params.concat(fields) : (params << Param.new("body", "", "json"))
    elsif call_text.matches?(/(?:io|ioutil)\.ReadAll\([^)]*\.Body\)/)
      params << Param.new("body", "", "json")
    end

    append_regex_param(params, call_text, /\.URL\s*\.\s*Query\s*\(\s*\)\s*\.\s*(?:Get|Has)\s*\(\s*["`]([^"`]+)["`]/, "query")
    ctx.try &.queries.each do |name|
      call_text.scan(/(?<![\w.])#{Regex.escape(name)}\s*(?:\[\s*"([^"]+)"\s*\]|\.\s*(?:Get|Has)\s*\(\s*"([^"]+)"\s*\))/) do |m|
        params << Param.new(m[1]? || m[2], "", "query")
      end
    end
    append_regex_param(params, call_text, /\.PostForm\s*\.\s*Get\s*\(\s*["`]([^"`]+)["`]/, "form")
    append_regex_param(params, call_text, /\.Form\s*\.\s*Get\s*\(\s*["`]([^"`]+)["`]/, form_value_param_type(http_method))
    append_regex_param(params, call_text, /\.PostFormValue\s*\(\s*["`]([^"`]+)["`]/, "form")
    append_regex_param(params, call_text, /\.FormValue\s*\(\s*["`]([^"`]+)["`]/, form_value_param_type(http_method))
    # `r.PostForm["a"]` / `r.Form["i"]`: the parsed form, read by key.
    append_regex_param(params, call_text, /\.PostForm\s*\[\s*["`]([^"`]+)["`]\s*\]/, "form")
    append_regex_param(params, call_text, /(?<!Post)\.Form\s*\[\s*["`]([^"`]+)["`]\s*\]/, form_value_param_type(http_method))
    params.concat(request_header_params(call_text, ctx.try(&.requests)))
    append_regex_param(params, call_text, /\.Cookie\s*\(\s*["`]([^"`]+)["`]/, "cookie")
    append_regex_param(params, call_text, /\.PathValue\s*\(\s*["`]([^"`]+)["`]/, "path")

    dedupe_params(params)
  end

  # `header_params`, keeping only reads off one of `requests` (or a
  # framework's `.Request`) when the request parameters are known.
  private def request_header_params(text : String, requests : Set(String)?) : Array(Param)
    return header_params(text) unless requests
    params = [] of Param
    text.scan(HEADER_READ_RE) do |m|
      head = text[0, m.begin]
      receiver = head.match(/([A-Za-z_]\w*)(?:\s*\(\s*\))?\s*\z/).try(&.[1]) || next
      next unless requests.includes?(receiver) || receiver == "Request"
      params << Param.new(m[1]? || m[2], "", "header")
    end
    params
  end

  # The params a helper call reads by its name alone (`QueryInt64Param(r,
  # "page")`), for a helper whose definition is not read.
  private def named_helper_params(call : LibTreeSitter::TSNode, source : String, http_method : String) : Array(Param)
    leaf = call_function_leaf(call, source)
    param_type = helper_param_type(leaf, http_method) || return [] of Param
    name = first_string_arg(call, source) || return [] of Param
    [Param.new(name, "", param_type)]
  end

  # The JSON names of the struct a decoded body fills (`var req T` then
  # `Decode(&req)`): a field's `json` tag, or an exported field's own name;
  # a `json:"-"` field is never bound. Nil when the target does not resolve
  # to a struct with such a field.
  private def decoded_fields(call_text : String, ctx : Context?) : Array(Param)?
    ctx || return
    resolver = ctx.resolver || return
    file = ctx.file || return
    target = call_text.match(DECODE_TARGET) || return
    fields = resolver.structs.target_fields(ctx.lines, target[1], file) || return
    names = fields.compact_map do |field|
      tag = field.tag.match(/(?:\A|\s)json:"([^"]*)"/)
      name = tag ? tag[1].split(',').first : ""
      next if name == "-"
      next name unless name.empty?
      field.name if !field.embedded && field.name[0]?.try(&.uppercase?)
    end
    names.empty? ? nil : names.uniq.map { |name| Param.new(name, "", "json") }
  end

  private def append_regex_param(params : Array(Param), call_text : String, regex : Regex, param_type : String)
    if match = call_text.match(regex)
      params << Param.new(match[1], "", param_type)
    end
  end

  private def helper_function_body_for_call(call : LibTreeSitter::TSNode,
                                            source : String,
                                            external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                            external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))) : Noir::GoCalleeExtractor::FunctionBody?
    function = Noir::TreeSitter.field(call, "function")
    return unless function

    case Noir::TreeSitter.node_type(function)
    when "identifier"
      name = Noir::TreeSitter.node_text(function, source)
      external_functions[name]?
    when "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      return unless field
      method_name = Noir::TreeSitter.node_text(field, source)
      return if helper_param_type(method_name, "") || method_name == "Get" || method_name == "Decode"
      if (methods = external_methods[method_name]?) && methods.size == 1
        methods.first
      end
    end
  end

  private def helper_param_type(name : String, http_method : String) : String?
    case name
    when "HasQueryParam"
      "query"
    when "PathValue", "PathParam", "URLParam"
      "path"
    else
      if name.matches?(/^Query[A-Za-z0-9_]*Param(?:List)?$/)
        "query"
      elsif name.matches?(/^Route[A-Za-z0-9_]*Param$/)
        "path"
      elsif name.matches?(/^Path[A-Za-z0-9_]*Param$/)
        "path"
      elsif name.matches?(/^Form[A-Za-z0-9_]*Param$/)
        form_value_param_type(http_method)
      elsif name.matches?(/^Header[A-Za-z0-9_]*Param$/)
        "header"
      elsif name.matches?(/^Cookie[A-Za-z0-9_]*Param$/)
        "cookie"
      end
    end
  end

  private def form_value_param_type(http_method : String) : String
    case http_method
    when "GET", "HEAD", "QUERY", ""
      "query"
    else
      "form"
    end
  end

  private def first_string_arg(call : LibTreeSitter::TSNode, source : String) : String?
    args = Noir::TreeSitter.field(call, "arguments")
    return unless args

    Noir::TreeSitter.each_named_arg(args) do |arg|
      if string_literal_node?(arg)
        return decode_string_literal(arg, source)
      end
    end

    nil
  end

  private def find_handler_args(call : LibTreeSitter::TSNode) : Array(LibTreeSitter::TSNode)
    found = [] of LibTreeSitter::TSNode
    args = Noir::TreeSitter.field(call, "arguments")
    return found unless args

    first = true
    Noir::TreeSitter.each_named_arg(args) do |arg|
      if first
        first = false
        next
      end
      next if string_literal_node?(arg)
      found << arg
    end

    found
  end

  private def fallback_handler_arg_from_call(call : LibTreeSitter::TSNode,
                                             source : String,
                                             external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                             external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))) : LibTreeSitter::TSNode?
    args = Noir::TreeSitter.field(call, "arguments")
    return unless args

    Noir::TreeSitter.each_named_arg(args) do |arg|
      next if string_literal_node?(arg)
      candidate = unwrap_handler_arg(arg, source)
      return candidate if handler_candidate?(candidate, source, external_functions, external_methods)
    end

    nil
  end

  private def handler_candidate?(node : LibTreeSitter::TSNode,
                                 source : String,
                                 external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                 external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody))) : Bool
    case Noir::TreeSitter.node_type(node)
    when "func_literal", "call_expression"
      true
    when "identifier"
      external_functions.has_key?(Noir::TreeSitter.node_text(node, source))
    when "selector_expression"
      field = Noir::TreeSitter.field(node, "field")
      return false unless field
      methods = external_methods[Noir::TreeSitter.node_text(field, source)]?
      !methods.nil? && methods.size == 1
    else
      false
    end
  end

  private def unwrap_handler_arg(arg : LibTreeSitter::TSNode, source : String, depth : Int32 = 0) : LibTreeSitter::TSNode
    return arg if depth > 4
    return arg unless Noir::TreeSitter.node_type(arg) == "call_expression"

    function = Noir::TreeSitter.field(arg, "function")
    wrapper_name = function ? call_text(function, source) : ""
    return arg unless handler_wrapper_call?(wrapper_name)

    args = Noir::TreeSitter.field(arg, "arguments")
    return arg unless args

    inner : LibTreeSitter::TSNode? = nil
    Noir::TreeSitter.each_named_arg(args) do |child|
      next if string_literal_node?(child)
      inner = child
      break unless wrapper_name == "append"
    end

    if found = inner
      unwrap_handler_arg(found, source, depth + 1)
    else
      arg
    end
  end

  private def handler_wrapper_call?(name : String) : Bool
    return true if name == "append"
    return true if name == "HandlerFunc" || name.ends_with?(".HandlerFunc")
    return true if name == "StripPrefix" || name.ends_with?(".StripPrefix")
    return true if name == "Use" || name.ends_with?(".Use")
    false
  end

  private def call_function_leaf(call : LibTreeSitter::TSNode, source : String) : String
    function = Noir::TreeSitter.field(call, "function")
    return "" unless function
    case Noir::TreeSitter.node_type(function)
    when "identifier"
      Noir::TreeSitter.node_text(function, source)
    when "selector_expression"
      field = Noir::TreeSitter.field(function, "field")
      field ? Noir::TreeSitter.node_text(field, source) : ""
    else
      ""
    end
  end

  private def call_text(node : LibTreeSitter::TSNode, source : String) : String
    case Noir::TreeSitter.node_type(node)
    when "identifier"
      Noir::TreeSitter.node_text(node, source)
    when "selector_expression"
      operand = Noir::TreeSitter.field(node, "operand")
      field = Noir::TreeSitter.field(node, "field")
      return "" unless operand && field
      left = call_text(operand, source)
      left.empty? ? Noir::TreeSitter.node_text(field, source) : "#{left}.#{Noir::TreeSitter.node_text(field, source)}"
    else
      ""
    end
  end

  private def string_literal_node?(node : LibTreeSitter::TSNode) : Bool
    ty = Noir::TreeSitter.node_type(node)
    ty == "interpreted_string_literal" || ty == "raw_string_literal"
  end

  private def decode_string_literal(node : LibTreeSitter::TSNode, source : String) : String
    text = Noir::TreeSitter.node_text(node, source)
    return text[1...-1] if text.size >= 2 && ((text.starts_with?("\"") && text.ends_with?("\"")) || (text.starts_with?("`") && text.ends_with?("`")))
    text
  end

  private def dedupe_params(params : Array(Param)) : Array(Param)
    deduped = [] of Param
    params.each { |param| push_param(deduped, param) }
    deduped
  end

  private def push_param(params : Array(Param), param : Param)
    return if param.name.empty? || param.param_type.empty?
    return if params.any? { |existing| existing.name == param.name && existing.param_type == param.param_type }
    params << param
  end
end
