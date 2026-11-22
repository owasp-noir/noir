require "../ext/tree_sitter/tree_sitter"
require "../models/endpoint"
require "./go_callee_extractor"
require "./go_binding"
require "./go_json_map_reads"
require "./go_named_handler"
require "../utils/c_comments"

module Noir::GoRequestParamExtractor
  alias GoBinding = Noir::GoBinding
  extend self

  # Include an accessor called by the request helper at the third hop. The
  # cache keeps the remaining walk depth separate for each call site.
  MAX_HELPER_DEPTH = 4

  record ForwardedBinding, kind : String, parameter : String, fallback : GoBinding::Destination?

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

    getter framework : String?
    # Names are deliberately unqualified. A collision can admit an extra walk,
    # but the normal receiver, package and argument resolution still decides it.
    @binding_helpers : Set(String)?

    @helpers_indexed = false
    @forwarders = Hash(Noir::GoCalleeExtractor::FunctionBody, Array(ForwardedBinding)?).new
    @forwarder_mutex = Mutex.new

    def binding_helpers : Set(String)?
      return unless @framework
      @mutex.synchronize do
        unless @helpers_indexed
          @binding_helpers = GoRequestParamExtractor.binding_helpers(@file_contents)
          @helpers_indexed = true
        end
        @binding_helpers
      end
    end

    def with_binding_tree(text : String, file : String, named = text.lstrip.starts_with?("func "), &)
      if named && (tree = Fiber.current.noir_go_tree) && tree.source.same?(@file_contents[file]?) &&
         (node = tree.top_level_node(text))
        yield node, tree.source
      else
        source = named ? "package p\n#{text}" : "package p\nfunc _() {\n#{text}\n}"
        Noir::TreeSitter.parse_go(source) { |root| yield root, source }
      end
    end

    def forwarded_bindings(fn) : Array(ForwardedBinding)?
      @forwarder_mutex.synchronize do
        @forwarders.put_if_absent(fn) { GoRequestParamExtractor.forwarded_bindings(fn, self) }
      end
    end

    @factory_sites = Hash(String, GoBinding::FactorySites).new

    def receiver_factories(file, offset, handler, receiver) : GoBinding::Arguments
      sites = @mutex.synchronize { @factory_sites[file] ||= GoBinding.factory_sites(@file_contents[file], file) }
      result = GoBinding::Arguments.new
      sites[{offset, handler}]?.try &.each { |field, dest| result["#{receiver}.#{field}()"] = dest }
      result
    end

    def initialize(@bodies, @file_contents : Hash(String, String), @import_dirs : Hash(String, String), @framework : String? = nil, structs : Noir::GoStructFields::Index? = nil)
      @structs = structs || Noir::GoStructFields::Index.new(@file_contents, @import_dirs)
      @file_contents.each_key do |path|
        (@files_by_dir[File.dirname(path)] ||= [] of String) << path unless path.ends_with?("_test.go")
      end
    end

    @callbacks = Hash(Tuple(Noir::GoCalleeExtractor::FunctionBody, String), Set(String)).new

    def invoked_callbacks(wrapper, verb)
      key = {wrapper, verb}
      found = @mutex.synchronize { @callbacks[key]? }
      return found if found
      invoked = Set(String).new
      with_binding_tree(wrapper.source, wrapper.file_path) do |node, source|
        requests = wrapper.source.scan(REQUEST_PARAM).map(&.[1]).to_set
        GoRequestParamExtractor.reachable_nodes(node, source, verb, requests) do |child|
          next unless Noir::TreeSitter.node_type(child) == "call_expression"
          invoked << GoBinding.node_field(child, "function", source).rchop(".ServeHTTP")
        end
      end
      @mutex.synchronize { @callbacks[key] = invoked }
    end

    # Resolve a method value on a typed receiver or a chain of struct fields.
    # Each field's type is interpreted using the imports in its own file.
    def method_value(text, at, source, file, bound) : Noir::GoCalleeExtractor::FunctionBody?
      receiver, _, name = text.rpartition('.')
      return unless receiver.matches?(/\A\w+(?:\.\w+)*\z/) && name.matches?(GoBinding::IDENT)
      if !receiver.includes?('.') && (fn = imported_function(file, receiver, name))
        return fn
      end
      dest = receiver_type(receiver, at, source, file, bound) || return
      type = dest.type.lchop('*')
      qualifier, _, bare = type.rpartition('.')
      dir = qualifier.empty? ? File.dirname(dest.file) : aliases(dest.file)[qualifier]?.try { |path| @import_dirs[path]? }
      return unless dir
      @bodies.methods_for(dir)[name]?.try &.find { |candidate| candidate.source.match(Noir::GoNamedHandler::RECEIVER_RE).try(&.[2]) == bare }
    end

    private def receiver_type(text, at, source, file, bound) : GoBinding::Destination?
      return bound[text] if bound.has_key?(text)
      receiver, _, field = text.rpartition('.')
      return GoBinding.destination(text, at, source, file, bound) if receiver.empty?
      dest = receiver_type(receiver, at, source, file, bound) || return
      decl_file, fields = @structs.declaration(dest.type, dest.file) || return
      member = fields.find { |f| f.name == field } || return
      GoBinding::Destination.new(member.type, decl_file)
    end

    # Resolve a package-qualified function using the imports at the call site.
    def imported_function(file : String, qualifier : String, name : String) : Noir::GoCalleeExtractor::FunctionBody?
      import_path = aliases(file)[qualifier]? || return
      dir = @import_dirs[import_path]? || return
      @bodies.functions_for(dir)[name]?
    end

    def aliases(file : String) : Hash(String, String)
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
    requests : Set(String)? = nil, queries : Set(String) = Set(String).new, destinations : GoBinding::Arguments = GoBinding::Arguments.new, decoded_bytes : Bool = false, route_path : String? = nil

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
    list = (source.match(HELPER_PARAMS) || source.match(LITERAL_PARAMS)).try(&.[1]) || return
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

  # Completed top-level walks with no argument or receiver bindings. A Chi
  # registration and its named handler often ask exactly the same question.
  alias BodyKey = Tuple(Noir::GoCalleeExtractor::FunctionBody, String, String?)
  alias BodyParams = Hash(BodyKey, Array(Param))

  private class WalkCache
    @entries = Hash(String, Tuple(Int32, Array(Param))).new
    @prior_entries = 0
    @borrowed = false
    @body_params : BodyParams?

    def initialize(@body_params = nil)
    end

    def begin_handler
      @prior_entries = @entries.size
      @borrowed = false
    end

    def fetch?(key)
      if hit = @entries[key]?
        @borrowed = true if hit[0] < @prior_entries
        hit[1]
      end
    end

    def store(key, params)
      @entries[key] = {@entries.size, params}
    end

    def standalone_results
      @body_params unless @borrowed
    end
  end

  # The params the handler definition `fn` reads (and the helpers it calls,
  # through `resolver`), for a route answering `http_method`.
  def params_for_body(fn : Noir::GoCalleeExtractor::FunctionBody, http_method : String, resolver : Resolver, route_path : String? = nil, body_params : BodyParams? = nil) : Array(Param)
    key = {fn, http_method, route_path}
    if body_params && (cached = body_params[key]?)
      return cached.map(&.detached_copy)
    end
    dir = File.dirname(fn.file_path)
    params = [] of Param
    append_function_params(fn, http_method, resolver.bodies.functions_for(dir), resolver.bodies.methods_for(dir),
      WalkCache.new, Set(String).new, params, 0, resolver, route_path: route_path)
    body_params[key] = params.map(&.detached_copy) if body_params
    params
  end

  # Only these operations can emit parameters in the framework binding walk.
  # Include any reference to a potential helper, even a value or a comment.
  # Exact call resolution happens in collect_params_in_body.
  BINDING_READ = /Bind|Decode|Unmarshal|ReadAll/
  GO_NAME      = /[\p{L}_][\p{L}\p{Nd}_]*/

  # Compute backwards reachability once for this resolver. A helper may
  # forward through several packages or share its method name with another
  # type. Union all definitions and keep cycles reachable from a read.
  @@helper_indexes = Hash(UInt64, Set(String)?).new
  @@helper_index_mutex = Mutex.new

  Noir::ExtractionResultCache.register_clearer { @@helper_index_mutex.synchronize { @@helper_indexes.clear } }

  def binding_helpers(files : Hash(String, String)) : Set(String)?
    # Gin and Echo can analyze the same inventory. Membership and contents
    # determine reachability, independently of the adapter and import map.
    @@helper_index_mutex.synchronize do
      @@helper_indexes.put_if_absent(files.hash) { build_binding_helpers(files) }
    end
  end

  private def build_binding_helpers(files) : Set(String)?
    reachable = Set(String).new
    candidates = [] of Tuple(String, String)
    files.each do |path, source|
      next if path.ends_with?("_test.go")
      next unless source.matches?(FRAMEWORK_CONTEXT) || source.matches?(REQUEST_PARAM)
      functions, methods = Noir::GoCalleeExtractor.collect_top_level_bodies(source, path)
      functions.each { |name, fn| index_binding_helper(name, fn, reachable, candidates) }
      methods.each { |name, bodies| bodies.each { |fn| index_binding_helper(name, fn, reachable, candidates) } }
    rescue
      # An unrelated package can time out. An incomplete index cannot prove
      # a helper unreachable: fall back to ordinary demand-driven resolution.
      return
    end

    names = reachable.dup
    candidates.each { |(name, _)| names << name }
    callers = Hash(String, Set(String)).new
    candidates.each do |(caller, text)|
      text.scan(GO_NAME) do |match|
        name = match[0]
        (callers[name] ||= Set(String).new) << caller if name != caller && names.includes?(name)
      end
    end
    pending = reachable.to_a
    while callee = pending.pop?
      callers[callee]?.try &.each { |caller| pending << caller if reachable.add?(caller) }
    end
    reachable
  end

  private def index_binding_helper(name, fn, reachable, candidates)
    signature = fn.source.match(HELPER_PARAMS) || return
    return unless request_helper?(signature[1], framework: true)
    if fn.source.matches?(BINDING_READ)
      reachable << name
    else
      candidates << {name, fn.source}
    end
  end

  # In a lone r.POST("/path", handler) the reference is never called.
  # More complex or partial registration text keeps the broad name check.
  NAMED_REGISTRATION = /\A\s*\w+(?:\.\w+)*\.(\w+)\(\s*"(?:[^"\\]|\\.)*"\s*,\s*\w+(?:\.\w+)*\s*\)\s*\z/

  private def mentions_helper?(text, helpers) : Bool
    if registration = text.match(NAMED_REGISTRATION)
      return helpers.includes?(registration[1])
    end
    text.scan(GO_NAME) { |m| return true if helpers.includes?(m[0]) }
    false
  end

  # Attributed lines from the framework adapters can be a named declaration
  # or an inline registration. Wrap the latter as a Go statement list.
  def binding_params(lines : Array(String), file : String, method : String, resolver : Resolver, destinations = GoBinding::Arguments.new) : Array(Param)
    return [] of Param if lines.empty?
    text = lines.join("\n")
    if (helpers = resolver.binding_helpers) && !text.matches?(BINDING_READ)
      return [] of Param unless mentions_helper?(text, helpers)
    end
    ctx = Context.new(resolver, file, lines, Hash(String, String).new, destinations: destinations)
    result = [] of Param
    dir = File.dirname(file)
    resolver.with_binding_tree(text, file) do |root, source|
      collect_params_in_body(root, source, method, resolver.bodies.functions_for(dir), resolver.bodies.methods_for(dir),
        WalkCache.new, Set(String).new, result, 0, ctx)
    end
    result
  end

  def params_for_routes(source : String,
                        routes : Array(Noir::TreeSitterGoRouteExtractor::Route),
                        external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                        external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                        resolver : Resolver? = nil,
                        path : String? = nil, destinations = GoBinding::Arguments.new, chain_method : String? = nil, rooted = false, body_params : BodyParams? = nil)
    by_route = Hash(Tuple(Int32, String, String), Array(Param)).new
    return by_route if routes.empty?
    registrations = routes.group_by(&.offset)
    bindings = path && resolver ? unshadowed(resolver.constants(File.dirname(path)), source) : Hash(String, String).new
    ctx = Context.new(resolver, path, source.lines, bindings, destinations: destinations)

    cache = WalkCache.new(body_params)
    Noir::TreeSitter.parse_go(source) do |root|
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "call_expression"
        offset = LibTreeSitter.ts_node_end_byte(node).to_i
        hits = registrations[offset]? || next
        handler_args = Noir::GoCalleeExtractor.find_handler_args(node, source)
        if chain_method
          append_chained_middleware(node, source, handler_args, chain_method)
        end
        hits.each do |route|
          route_path = route.path if rooted && !route.prefix_unresolved? && !route.path.matches?(/[{:*]/)
          route_ctx = ctx.copy_with(route_path: route_path)
          Noir::TreeSitterGoRouteExtractor.fan_out_verbs(route.verb).each do |http_method|
            params = [] of Param
            handler_args.each do |handler_arg|
              collect_params_for_handler_arg(
                unwrap_handler_arg(handler_arg, source),
                source,
                http_method,
                external_functions,
                external_methods,
                cache,
                Set(String).new,
                params,
                route_ctx
              )
            end
            by_route[{offset, http_method, route.path}] = dedupe_params(params) unless params.empty?
          end
        end
      end
    end

    by_route
  end

  private def collect_params_for_handler_arg(handler_arg : LibTreeSitter::TSNode,
                                             source : String,
                                             http_method : String,
                                             external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                             external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                             cache : WalkCache,
                                             visiting : Set(String),
                                             sink : Array(Param),
                                             ctx : Context)
    case Noir::TreeSitter.node_type(handler_arg)
    when "func_literal"
      if body = Noir::TreeSitter.field(handler_arg, "body")
        # The closure's own declarations, not the first of the file's.
        text = Noir::TreeSitter.node_text(handler_arg, source)
        literal_ctx = ctx.copy_with(lines: text.lines, requests: request_params(text),
          queries: text.scan(QUERY_ALIAS).map(&.[1]).to_set)
        collect_params_in_body(body, source, http_method, external_functions, external_methods, cache, visiting, sink, 0, literal_ctx)
      end
    when "identifier"
      name = Noir::TreeSitter.node_text(handler_arg, source)
      if fn = external_functions[name]?
        append_function_params(fn, http_method, external_functions, external_methods, cache, visiting, sink, 0, ctx.resolver, route_path: ctx.route_path)
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
                                             cache : WalkCache,
                                             visiting : Set(String),
                                             sink : Array(Param),
                                             ctx : Context)
    field = Noir::TreeSitter.field(handler_arg, "field")
    return unless field

    method_name = Noir::TreeSitter.node_text(field, source)
    receiver = GoBinding.node_field(handler_arg, "operand", source)
    fn = if (resolver = ctx.resolver) && (file = ctx.file)
           resolver.method_value(Noir::TreeSitter.node_text(handler_arg, source), handler_arg, source, file, ctx.destinations)
         end
    methods = external_methods[method_name]?
    fn ||= methods.first if methods && methods.size == 1
    return unless fn
    target = fn.source.match(Noir::GoNamedHandler::RECEIVER_RE).try(&.[1]?)
    bindings = target ? GoBinding.receiver_fields(receiver, handler_arg, source, ctx.destinations, target) : GoBinding::Arguments.new
    append_function_params(fn, http_method, external_functions, external_methods, cache, visiting, sink, 0, ctx.resolver, destinations: bindings, route_path: ctx.route_path)
  end

  private def append_function_params(fn : Noir::GoCalleeExtractor::FunctionBody,
                                     http_method : String,
                                     external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                     external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                     cache : WalkCache,
                                     visiting : Set(String),
                                     sink : Array(Param),
                                     depth : Int32,
                                     resolver : Resolver? = nil,
                                     arg_bindings : Hash(String, String) = Hash(String, String).new,
                                     destinations : GoBinding::Arguments = GoBinding::Arguments.new, decoded_bytes = false, route_path : String? = nil)
    key = "#{fn.file_path}:#{fn.start_row}:#{http_method}:#{arg_bindings.to_a.sort!.join(',')}:#{destinations}:#{depth}:#{decoded_bytes}:#{route_path}"
    cache.begin_handler if depth == 0
    if cached = cache.fetch?(key)
      cached.each { |param| push_param(sink, param) }
      return
    end

    visit_key = "#{fn.file_path}:#{fn.start_row}"
    return if visiting.includes?(visit_key)
    if resolver && resolver.framework && (reads = resolver.forwarded_bindings(fn))
      reads.each do |binding|
        dest = destinations.fetch(binding.parameter, binding.fallback)
        GoBinding.params(binding.kind, http_method, dest, resolver.structs).each { |param| push_param(sink, param) }
      end
      return
    end
    visiting << visit_key
    cutoffs = Fiber.current.noir_ts_walk_cutoffs

    params = [] of Param
    dir = File.dirname(fn.file_path)
    bindings = arg_bindings
    if resolver
      # The body's own package decides what its helper calls mean.
      external_functions = resolver.bodies.functions_for(dir)
      external_methods = resolver.bodies.methods_for(dir)
      bindings = unshadowed(resolver.constants(dir), fn.source).merge(arg_bindings)
    end
    ctx = Context.new(resolver, fn.file_path, fn.source.lines, bindings, request_params(fn.source),
      fn.source.scan(QUERY_ALIAS).map(&.[1]).to_set, destinations, decoded_bytes, route_path)
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
    result = dedupe_params(params)
    cache.store(key, result)
    # A nested hit may have been computed with different ancestors in the
    # recursion guard. Only export results reproducible from an empty cache.
    if depth == 0 && (completed = cache.standalone_results) && cutoffs == Fiber.current.noir_ts_walk_cutoffs &&
       arg_bindings.empty? && destinations.empty? && !decoded_bytes
      completed[{fn, http_method, route_path}] = result
    end
    result.each { |param| push_param(sink, param) }
  end

  private def collect_params_in_body(body : LibTreeSitter::TSNode,
                                     source : String,
                                     http_method : String,
                                     external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                     external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                     cache : WalkCache,
                                     visiting : Set(String),
                                     sink : Array(Param),
                                     depth : Int32,
                                     ctx : Context)
    helpers = ctx.resolver.try(&.binding_helpers)
    if (map_resolver = ctx.resolver) && (map_file = ctx.file) && (requests = ctx.requests) &&
       ctx.lines.any? { |line| line.includes?("range ") || line.includes?("map[") }
      flow = JSONMapReads.new(map_resolver, map_file, http_method)
      flow.analyze(body, source, requests.to_h { |name| {name, :request} })
      flow.names.each { |name| push_param(sink, Param.new(name, "", "json")) }
    end
    decoded_reads = consumed_byte_reads(body, source, ctx)
    reachable_nodes(body, source, http_method, ctx.requests, ctx.route_path) do |node|
      type = Noir::TreeSitter.node_type(node)
      # `items := r.Form["i"]` reads the form outside any call.
      if type == "index_expression" && !ctx.resolver.try(&.framework)
        extract_params_from_call(node, source, http_method, ctx).each { |param| push_param(sink, param) }
      end
      if type == "for_statement" && !ctx.resolver.try(&.framework)
        each_range_literal(node, source, ctx) do |loop_body, loop_ctx|
          collect_params_in_body(loop_body, source, http_method, external_functions, external_methods, cache, visiting, sink, depth, loop_ctx)
        end
      end
      next unless type == "call_expression"

      # The helper (or io.ReadAll) supplying bytes to json.Unmarshal
      # is accounted for at the decoding call with its actual destination.
      consumed = decoded_reads.includes?(LibTreeSitter.ts_node_start_byte(node))
      if binding = bound_params(node, source, http_method, ctx)
        binding.each { |param| push_param(sink, param) }
        next
      end
      if !consumed && !ctx.decoded_bytes && call_function_leaf(node, source) == "ReadAll" &&
         GoBinding.node_field(node, "function", source).matches?(/\A(?:io|ioutil)\.ReadAll\z/) &&
         (args = Noir::TreeSitter.field(node, "arguments")) && (arg = Noir::TreeSitter.first_named_arg(args)) &&
         request_body?(Noir::TreeSitter.node_text(arg, source), node, source, ctx)
        push_param(sink, Param.new("body", "", "json"))
      end
      unless ctx.resolver.try(&.framework)
        extract_params_from_call(node, source, http_method, ctx).each { |param| push_param(sink, param) }
      end

      if depth < MAX_HELPER_DEPTH && ctx.requests && (resolver = ctx.resolver) && (file = ctx.file)
        dispatch_targets(node, source, ctx, resolver, file, http_method).each do |fn|
          append_function_params(fn, http_method, external_functions, external_methods, cache, visiting, sink, depth + 1,
            resolver, helper_bindings(fn, node, source, ctx), destination_arguments(fn, node, source, ctx), route_path: ctx.route_path)
        end
      end
      next if helpers && !helpers.includes?(call_function_leaf(node, source))
      imported = depth < MAX_HELPER_DEPTH ? imported_helper_for_call(node, source, ctx) : nil
      if imported
        # Read the helper's definition, with its parameters bound to the
        # literals passed here; its name decides only when that reads
        # nothing off the request.
        found = [] of Param
        append_function_params(imported, http_method, external_functions, external_methods, cache, visiting, found, depth + 1,
          ctx.resolver, helper_bindings(imported, node, source, ctx), destination_arguments(imported, node, source, ctx), consumed, ctx.route_path)
        found = named_helper_params(node, source, http_method) if found.empty? && !ctx.resolver.try(&.framework)
        found.each { |param| push_param(sink, param) }
        next
      end
      named_helper_params(node, source, http_method).each { |param| push_param(sink, param) } unless ctx.resolver.try(&.framework)

      next if depth >= MAX_HELPER_DEPTH
      if fn = helper_function_body_for_call(node, source, external_functions, external_methods, ctx)
        if ctx.resolver.try(&.framework)
          next unless request_helper?(fn.source.match(HELPER_PARAMS).try(&.[1]) || "", framework: true)
        end
        append_function_params(fn, http_method, external_functions, external_methods, cache, visiting, sink, depth + 1,
          ctx.resolver, helper_bindings(fn, node, source, ctx), destination_arguments(fn, node, source, ctx), consumed, ctx.route_path)
      end
    end
  end

  # A definite return in a method-specific branch excludes later statements
  # in the same block. Unknown conditions keep both paths open.
  METHOD_CONDITION = /\A(\w+)\.Method\s*(==|!=)\s*(?:http\.Method(\w+)|"([A-Z]+)")\z/

  def reachable_nodes(node, source, verb, requests, route_path = nil, &block : LibTreeSitter::TSNode ->) : Bool
    yield node
    case Noir::TreeSitter.node_type(node)
    when "return_statement"
      Noir::TreeSitter.each_named_arg(node) { |child| reachable_nodes(child, source, verb, requests, route_path, &block) }
      true
    when "block", "statement_list"
      Noir::TreeSitter.each_named_arg(node) do |child|
        return true if reachable_nodes(child, source, verb, requests, route_path, &block)
      end
      false
    when "if_statement"
      condition = GoBinding.node_field(node, "condition", source)
      take = if verb != "ANY" && (m = condition.match(METHOD_CONDITION)) && requests.try(&.includes?(m[1]))
               ((m[3]? || m[4]).upcase == verb) == (m[2] == "==")
             elsif route_path && (m = condition.match(/\A(\w+)\.URL\.Path\s*(==|!=)\s*"([^"\\]*)"\z/)) && requests.try(&.includes?(m[1]))
               (m[3] == route_path) == (m[2] == "==")
             end
      unless take.nil?
        if init = Noir::TreeSitter.field(node, "initializer")
          reachable_nodes(init, source, verb, requests, route_path, &block)
        end
        branch = Noir::TreeSitter.field(node, take ? "consequence" : "alternative")
        return branch ? reachable_nodes(branch, source, verb, requests, route_path, &block) : false
      end
      Noir::TreeSitter.each_named_arg(node) { |child| reachable_nodes(child, source, verb, requests, route_path, &block) }
      false
    else
      Noir::TreeSitter.each_named_arg(node) { |child| reachable_nodes(child, source, verb, requests, route_path, &block) }
      false
    end
  end

  # Follow calls receiving the request. For a wrapper immediately applied to
  # (w, r), follow only callback parameters its definition actually invokes.
  private def dispatch_targets(call, source, ctx, resolver, file, verb)
    targets = [] of Noir::GoCalleeExtractor::FunctionBody
    args = Noir::TreeSitter.field(call, "arguments") || return targets
    requests = ctx.requests || return targets
    takes_request = false
    Noir::TreeSitter.each_named_arg(args) do |arg|
      if Noir::TreeSitter.node_type(arg) == "identifier" && requests.includes?(Noir::TreeSitter.node_text(arg, source))
        takes_request = true
        break
      end
    end
    return targets unless takes_request
    fn = Noir::TreeSitter.field(call, "function") || return targets
    case Noir::TreeSitter.node_type(fn)
    when "selector_expression"
      text = Noir::TreeSitter.node_text(fn, source)
      if text.count('.') >= 2 && (method = resolver.method_value(text, call, source, file, ctx.destinations))
        targets << method
      end
    when "call_expression"
      factory = GoBinding.node_field(fn, "function", source)
      wrapper = resolver.method_value(factory, fn, source, file, ctx.destinations) ||
                resolver.bodies.functions_for(File.dirname(file))[factory]?
      params = wrapper.try(&.source.match(HELPER_PARAMS)).try(&.[1].split(',')) || return targets
      values = Noir::TreeSitter.field(fn, "arguments") || return targets
      i = 0
      Noir::TreeSitter.each_named_arg(values) do |arg|
        param = params[i]?.try(&.strip.split(/\s+/).first?)
        i += 1
        next unless param && wrapper && resolver.invoked_callbacks(wrapper, verb).includes?(param)
        name = Noir::TreeSitter.node_text(arg, source)
        target = resolver.method_value(name, arg, source, file, ctx.destinations) || resolver.bodies.functions_for(File.dirname(file))[name]?
        targets << target if target
      end
    when "identifier"
      name = Noir::TreeSitter.node_text(fn, source)
      if ctx.lines.any? { |line| line.includes?(name) && line.includes?('=') }
        GoBinding.assigned_methods(name, call, source).each do |value|
          if target = resolver.method_value(Noir::TreeSitter.node_text(value, source), value, source, file, ctx.destinations)
            targets << target
          end
        end
      end
    end
    targets
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
    fn if request_helper?(params, !resolver.framework.nil?)
  end

  FRAMEWORK_CONTEXT = /\b(?!context\.)\w+\.Context\b/

  private def request_helper?(params : String, framework : Bool) : Bool
    (params.matches?(REQUEST_PARAM) || (framework && params.matches?(FRAMEWORK_CONTEXT))) && !params.includes?("http.ResponseWriter")
  end

  private def destination_arguments(fn, call, source, ctx) : GoBinding::Arguments
    result = GoBinding::Arguments.new
    file = ctx.file || return result
    list = fn.source.match(HELPER_PARAMS).try(&.[1]) || return result
    return result unless list.matches?(REQUEST_PARAM) || request_helper?(list, !ctx.resolver.try(&.framework).nil?)
    names = list.split(',').map(&.strip.split(/\s+/).first?)
    args = Noir::TreeSitter.field(call, "arguments") || return result
    i = 0
    Noir::TreeSitter.each_named_arg(args) do |arg|
      name = names[i]?
      i += 1
      next unless name
      dest = GoBinding.destination(Noir::TreeSitter.node_text(arg, source), call, source, file, ctx.destinations)
      result[name] = dest if dest
    end
    result
  end

  GIN_BIND  = /\A(?:Should|Must)?Bind(JSON|Query|Header|Uri|With|BodyWith|BodyWithJSON|XML|YAML|TOML)?\z/
  GIN_KINDS = {"JSON" => "json", "BodyWithJSON" => "json", "Query" => "query", "Uri" => "uri",
               "Header" => "header", "Form" => "form", "FormPost" => "form", "FormMultipart" => "form"}
  ECHO_KINDS = {"Bind" => "echo", "BindBody" => "json", "BindJSON" => "json", "BindQuery" => "echo_query",
                "BindQueryParams" => "echo_query", "BindPath" => "param", "BindPathParams" => "param",
                "BindHeaders" => "echo_header", "BindXML" => "opaque", "BindYAML" => "opaque"}

  private def consumed_byte_reads(body, source, ctx) : Set(UInt32)
    reads = Set(UInt32).new
    return reads unless ctx.lines.any?(&.includes?("Unmarshal"))
    Noir::TreeSitter.walk(body) do |node|
      next unless Noir::TreeSitter.node_type(node) == "call_expression" && call_function_leaf(node, source) == "Unmarshal"
      qualifier = GoBinding.node_field(node, "function", source).rpartition('.').first
      next unless json_package?(qualifier, ctx)
      args = Noir::TreeSitter.field(node, "arguments") || next
      arg = Noir::TreeSitter.first_named_arg(args) || next
      name = Noir::TreeSitter.node_text(arg, source)
      if request_bytes?(name, node, source, ctx) && (value = GoBinding.local(name, node, source).try(&.value))
        reads << LibTreeSitter.ts_node_start_byte(value)
      end
    end
    reads
  end

  # Compile the binds of a leaf helper once. Response writing and validation
  # calls may surround a bind. A possible request-reading callee, byte read,
  # or target other than a formal parameter needs the context-sensitive walk.
  def forwarded_bindings(fn, resolver) : Array(ForwardedBinding)?
    return unless fn.source.includes?("Bind")
    helpers = resolver.binding_helpers || return
    reads = [] of ForwardedBinding
    complete = true
    ctx = Context.new(resolver, fn.file_path, fn.source.lines, Hash(String, String).new)
    resolver.with_binding_tree(fn.source, fn.file_path, named: true) do |root, source|
      # A borrowed node is the declaration; a standalone parse has a package
      # clause and the declaration beneath its root.
      decl = root
      if Noir::TreeSitter.node_type(root) == "source_file"
        Noir::TreeSitter.each_named_child(root) do |child|
          decl = child if {"function_declaration", "method_declaration"}.includes?(Noir::TreeSitter.node_type(child))
        end
      end
      body = Noir::TreeSitter.field(decl, "body") || return
      Noir::TreeSitter.walk(body) do |node|
        next unless complete && Noir::TreeSitter.node_type(node) == "call_expression"
        name = call_function_leaf(node, source)
        if name.includes?("Bind") && (binding = binding_target(node, source, ctx))
          if binding.is_a?(Tuple) && (read = forwarded_parameter(binding, node, source, ctx, fn.file_path))
            reads << read
          else
            complete = false
          end
        elsif helpers.includes?(name) || {"Decode", "DecodeJSON", "Unmarshal", "ReadAll"}.includes?(name)
          complete = false
        end
      end
    end
    reads if complete
  end

  private def forwarded_parameter(binding, call, source, ctx, file)
    kind, target = binding
    name = target.strip.lchop('&').strip
    return unless name.matches?(GoBinding::IDENT) && GoBinding.local(name, call, source).try(&.parameter)
    fallback = GoBinding.destination(target, call, source, file, ctx.destinations)
    ForwardedBinding.new(kind, name, fallback)
  end

  private def bound_params(call, source, method, ctx) : Array(Param)?
    case binding = binding_target(call, source, ctx)
    when Param
      [binding]
    when Tuple
      kind, target = binding
      dest = ctx.file.try { |file| GoBinding.destination(target, call, source, file, ctx.destinations) }
      GoBinding.params(kind, method, dest, ctx.resolver.try(&.structs))
    end
  end

  def binding_target(call, source, ctx) : (Tuple(String, String) | Param)?
    function = Noir::TreeSitter.field(call, "function") || return
    return unless Noir::TreeSitter.node_type(function) == "selector_expression"
    name = GoBinding.node_field(function, "field", source)
    return unless name.includes?("Bind") || {"Decode", "DecodeJSON", "Unmarshal"}.includes?(name)
    recv = GoBinding.node_field(function, "operand", source)
    args = [] of String
    Noir::TreeSitter.field(call, "arguments").try do |list|
      Noir::TreeSitter.each_named_arg(list) { |arg| args << Noir::TreeSitter.node_text(arg, source) }
    end
    target = args.first? || return
    framework = ctx.resolver.try(&.framework)
    package = ctx.file.try { |file| ctx.resolver.try(&.aliases(file)[recv]?) }
    if package == "github.com/oapi-codegen/runtime" && {"BindQueryParameter", "BindQueryParameterWithOptions"}.includes?(name)
      if (literal = args[3]?.try(&.match(/\A["`]([^"`]+)["`]\z/))) && args[4]?.try(&.matches?(/\A\w+\.URL\.Query\(\)\z/))
        return Param.new(literal[1], "", "query")
      end
      return
    end
    kind = case
           when package == "github.com/go-chi/render" && {"Bind", "DecodeJSON"}.includes?(name)
             target = args[1]? || return
             return unless name == "Bind" || request_body?(args[0], call, source, ctx)
             "json"
           when name == "Decode"
             decoder = recv.matches?(GoBinding::IDENT) ? GoBinding.local(recv, call, source).try(&.expression(source)) : recv
             return unless decoder && (m = decoder.match(/\A(\w+)\.NewDecoder\(\s*(.+?)\s*\)\z/m))
             return unless json_package?(m[1], ctx) && request_body?(m[2], call, source, ctx)
             "json"
           when name == "Unmarshal"
             return unless json_package?(recv, ctx) && request_bytes?(target, call, source, ctx)
             target = args[1]? || return
             "json"
           when framework == "gin" && !package && (m = name.match(GIN_BIND)) && context_receiver?(recv, call, source, ctx)
             suffix = m[1]?
             suffix = args[1]?.try(&.split('.').last) if {"With", "BodyWith"}.includes?(suffix)
             m[1]? ? GIN_KINDS.fetch(suffix || "", "opaque") : "gin"
           when framework == "echo" && ECHO_KINDS.has_key?(name) && (package.try(&.starts_with?("github.com/labstack/echo")) || context_receiver?(recv, call, source, ctx))
             target = args.last
             ECHO_KINDS[name]
           else
             return
           end
    {kind, target}
  end

  private def context_receiver?(name, call, source, ctx) : Bool
    return false unless name.matches?(GoBinding::IDENT)
    local = GoBinding.local(name, call, source) || return true
    type = local.type.lchop('*')
    # A context may be embedded in a project-defined handler context.
    return true if type.ends_with?(".Context")
    file = ctx.file || return false
    fields = ctx.resolver.try(&.structs.declaration(type, file))
    !!fields.try(&.last.any? { |field| field.embedded && field.type.ends_with?(".Context") })
  end

  private def json_package?(name, ctx) : Bool
    path = ctx.file.try { |file| ctx.resolver.try(&.aliases(file)[name]?) }
    path ? (path == "encoding/json" || path.ends_with?("/go-json") || path.ends_with?("/json-iterator/go")) : name == "json"
  end

  private def request_body?(expr, call, source, ctx) : Bool
    # http.MaxBytesReader(w, r.Body, limit) preserves the input stream.
    body = expr.match(/\Ahttp\.MaxBytesReader\([^,]+,\s*([^,]+),/).try(&.[1]) || expr
    if body.matches?(GoBinding::IDENT)
      body = GoBinding.local(body, call, source).try(&.expression(source)) || return false
    end
    m = body.match(/\A(\w+)(\.Request(?:\(\))?)?\.Body\z/) || return false
    return true if m[2]?
    requests = ctx.requests
    requests ? requests.includes?(m[1]) : GoBinding.local(m[1], call, source).try(&.type) == "*http.Request"
  end

  # Trace the bytes fed to json.Unmarshal to a request stream. A helper
  # returning []byte is inspected at its return, in its own package.
  private def request_bytes?(name, call, source, ctx, follow = true) : Bool
    return false unless name.matches?(GoBinding::IDENT)
    expr = GoBinding.local(name, call, source).try(&.expression(source)) || return false
    if m = expr.match(/\A(?:io|ioutil)\.ReadAll\((.+)\)\z/)
      return request_body?(m[1], call, source, ctx)
    end
    return false unless follow && (m = expr.match(/\A(?:(\w+)\.)?(\w+)\((\w+)\)\z/))
    request = GoBinding.local(m[3], call, source)
    return false unless ctx.requests.try(&.includes?(m[3])) || request.try(&.type) == "*http.Request"
    resolver = ctx.resolver || return false
    file = ctx.file || return false
    fn = if qualifier = m[1]?
           resolver.imported_function(file, qualifier, m[2])
         else
           resolver.bodies.functions_for(File.dirname(file))[m[2]]?
         end
    return false unless fn && request_params(fn.source) && fn.source.includes?("[]byte")
    helper_ctx = Context.new(resolver, fn.file_path, fn.source.lines, Hash(String, String).new, request_params(fn.source))
    found = false
    wrapped = "package p\n#{fn.source}"
    Noir::TreeSitter.parse_go(wrapped) do |root|
      Noir::TreeSitter.walk(root) do |node|
        next unless Noir::TreeSitter.node_type(node) == "return_statement"
        if returned = Noir::TreeSitter.node_text(node, wrapped).match(/\Areturn\s+(\w+)\s*(?:,|\z)/)
          found ||= request_bytes?(returned[1], node, wrapped, helper_ctx, false)
        end
      end
    end
    found
  end

  HELPER_PARAMS = /\Afunc\s*(?:\([^)]*\)\s*)?\w+\s*(?:\[.*?\]\s*)?\(([^)]*)\)/
  # A function literal's parameter list: `func(w http.ResponseWriter, r *http.Request)`.
  LITERAL_PARAMS = /\Afunc\s*\(([^)]*)\)/

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

  BOUND_NAME = /(?<![\w."`])([A-Za-z_]\w*)(?![\w"`(])/

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

    params.concat(accessor_params(call_text, http_method, ctx))
    dedupe_params(params)
  end

  # The `*http.Request` accessor reads on one source line (the query string,
  # the form, headers, cookies, `PathValue`), every one of them, for a route
  # answering `http_method`. For the adapters' line loops over a handler
  # whose definition is not walked.
  def line_params(line : String, http_method : String) : Array(Param)
    return [] of Param unless line.matches?(ACCESSOR_GATE)
    dedupe_params(accessor_params(line, http_method, nil))
  end

  # A word every read `accessor_params` matches contains.
  ACCESSOR_GATE = /Query|Form|Header|Cookie|PathValue/

  private def accessor_params(call_text : String, http_method : String, ctx : Context?) : Array(Param)
    params = [] of Param
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
    params
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

  private def append_regex_param(params : Array(Param), call_text : String, regex : Regex, param_type : String)
    call_text.scan(regex) { |match| params << Param.new(match[1], "", param_type) }
  end

  private def helper_function_body_for_call(call : LibTreeSitter::TSNode,
                                            source : String,
                                            external_functions : Hash(String, Noir::GoCalleeExtractor::FunctionBody),
                                            external_methods : Hash(String, Array(Noir::GoCalleeExtractor::FunctionBody)),
                                            ctx : Context) : Noir::GoCalleeExtractor::FunctionBody?
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
      receiver = GoBinding.node_field(function, "operand", source)
      return if ctx.file.try { |file| ctx.resolver.try(&.aliases(file).has_key?(receiver)) }
      return if receiver.includes?('.') && ctx.resolver && !ctx.resolver.try(&.framework)
      methods = external_methods[method_name]? || return
      if ctx.resolver.try(&.framework) && (file = ctx.file)
        if dest = GoBinding.destination(receiver, call, source, file, ctx.destinations)
          type = dest.type.lchop('*')
          return methods.find { |fn| fn.source.match(Noir::GoNamedHandler::RECEIVER_RE).try(&.[2]) == type }
        end
      end
      methods.first if methods.size == 1
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

  private def append_chained_middleware(call, source, args, chain_method)
    fn = Noir::TreeSitter.field(call, "function")
    while fn && (receiver = Noir::TreeSitter.field(fn, "operand")) && Noir::TreeSitter.node_type(receiver) == "call_expression"
      fn = Noir::TreeSitter.field(receiver, "function")
      break unless fn && GoBinding.node_field(fn, "field", source) == chain_method
      if list = Noir::TreeSitter.field(receiver, "arguments")
        Noir::TreeSitter.each_named_arg(list) { |arg| args << arg }
      end
    end
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
