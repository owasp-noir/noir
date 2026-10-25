require "../models/endpoint"
require "../utils/c_comments"
require "../utils/top_level_split"
require "./go_callee_extractor"
require "./go_route_extractor_ts"

# Named-handler attribution for the Go adapters' line loops.
#
# Those loops credit every accessor line (`c.Query("x")`) to the most recent
# route above it. That is right for inline closures, but a named handler's
# body (`r.GET("/a", listA)` ... `func listA(c) {...}`) sits below the LAST
# route of the file, so all of its accessors landed on that last route and
# the route that actually names the handler got nothing.
#
# Usage: build one per file from the extracted routes, `claim?` each line
# first (skip the legacy attribution when it returns true), `bind` every
# endpoint with its route, then `each_attribution` once the loop is done
# (the handler may be declared above or below its route).
#
# Every plain handler argument of a route is resolved — middleware too
# (`r.GET("/x", Auth, listX)` binds both bodies), and a middleware factory
# called with no arguments (`RateLimit()`) resolves to the factory body.
# Only unambiguous references are claimed; everything else keeps the legacy
# attribution:
#   * a bare `listA` resolves to the one `func listA` in this file;
#   * a selector `h.List` resolves to the one method `List` in this file
#     whose receiver type is the type `h` is declared with here, or, when
#     `h`'s type is not visible in this file, whose receiver is named `h`.
#     A receiver that is an imported package (`handlers.List`) never
#     resolves to a local method;
#   * given a `Scope`, a name not declared in this file is looked up in the
#     other files of its package (same rules), and `pkg.Fn` in the scanned
#     package `pkg` imports. Those bodies are attributed from their own
#     source, since the line loop never walks them;
#   * a function that registers routes itself is never claimed.
#
# A wrapped handler (`guard(func(c) { return listA(c) })`) binds every
# function its text names (`guard`, `listA`), and a bound body's own calls
# bind one hop further (`listA` calling `parseFilter(c)`). Any other body in
# the file that registers no route is claimed and credited to nobody: a
# helper below the last route is not part of that route.
class Noir::GoNamedHandler
  RECEIVER_RE  = /\Afunc\s*\(\s*(?:([A-Za-z_]\w*)\s+)?\*?\s*([A-Za-z_]\w*)/
  REFERENCE_RE = /\A\s*((?:[A-Za-z_]\w*\s*\.\s*)*)([A-Za-z_]\w*)\s*(?:\(\s*\))?\s*\z/
  # An unqualified name in a wrapped handler's text, and an unqualified call
  # in a bound body.
  NAME_RE = /(?<![\w.])[A-Za-z_]\w*/
  CALL_RE = /(?<![\w.])([A-Za-z_]\w*)\s*\(/
  # A function value in a wrapped handler's text: a name or selector that is
  # neither called nor a composite literal (`a.UpdateSubscriber` in
  # `pm(hasID(a.UpdateSubscriber), auth.PermX)`).
  VALUE_REF_RE = /(?<![\w.])((?:[A-Za-z_]\w*\s*\.\s*)*[A-Za-z_]\w*)(?![\w.]|\s*[({.])/
  CLOSURE_ARG  = /\bfunc\s*\(/
  # `recv.Method(` in a body: a call on a receiver.
  RECEIVER_CALL_RE = /(?<![\w.])([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)\s*\(/
  STRING_LITERAL   = /"(?:[^"\\]|\\.)*"|`[^`]*`/
  # The text after a definition's parameter list when it is a handler: no
  # result (`func(c *gin.Context)`, `func(w, r)`) or an `error` (`func(c
  # echo.Context) error`). A wrapper or factory returns the next handler
  # (`echo.HandlerFunc`, `func(...)`), so it never matches.
  HANDLER_RESULT = /\A\s*(?:error\s*)?\{/

  # Declarations that pin a name's type, scanned once per file (see
  # `declared_types`). Assignments are anchored at a statement start, so the
  # second name of `a, b := &X{}, newY()` is never typed `X`.
  # Group 2 is the type's package qualifier, if any.
  ASSIGNED_TYPE_RE = /(?:\A|[\n;{(])[ \t]*(?:var[ \t]+)?([A-Za-z_]\w*)[ \t]*:?=[ \t]*(?:&[ \t]*)?(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)[ \t]*\{/
  NEW_TYPE_RE      = /(?:\A|[\n;{(])[ \t]*(?:var[ \t]+)?([A-Za-z_]\w*)[ \t]*:?=[ \t]*new\([ \t]*(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)[ \t]*\)/
  # `name *T` as a parameter, receiver, struct field or `var`.
  DECLARED_TYPE_RE = /(?:\A|[\n(,]|\bvar)[ \t]*([A-Za-z_]\w*)[ \t]+\*?(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)/

  # Library middleware whose request read lives in a dependency the scan
  # never sees, with that read as the source line the adapters parse:
  # gin's BasicAuth checks the `Authorization` header.
  LIBRARY_READS = {
    {/\Agin\.BasicAuth(?:ForRealm)?\s*\(/, %(c.Request.Header.Get("Authorization"))},
  }

  # A route registration with a path literal (net/http's may lead with a
  # method, `"POST /items"`): the stand-in for the same-file route-row check
  # on a body declared in another file.
  ROUTE_CALL_RE = /\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|Get|Post|Put|Delete|Patch|Head|Options|Any|All|Handle|HandleFunc|Group|Route|Mount)\s*\(\s*"(?:[A-Z]+\s+)?\//

  # Where a handler not declared in the route's own file is looked up.
  # `bodies` covers every scanned package (built per directory on first
  # lookup and memoized, so a package is parsed once per analyzer);
  # `import_dirs` maps a local import path to its directory.
  record Scope,
    bodies : Noir::GoCalleeExtractor::LazyPackageBodies,
    import_dirs : Hash(String, String)

  # Test files are left out: an external `foo_test` package in the same
  # directory may reuse a handler's name.
  def self.scope(file_contents : Hash(String, String), import_dirs : Hash(String, String) = Hash(String, String).new) : Scope
    sources = file_contents.reject { |path, _| path.ends_with?("_test.go") }
    Scope.new(Noir::GoCalleeExtractor::LazyPackageBodies.new(sources), import_dirs)
  end

  # A body is keyed by its file and first row, so bodies from several files
  # never collide.
  alias Key = Tuple(String, Int32)

  @rows = Hash(Int32, Key).new
  @refs = Hash(String, Array(Key)).new
  @lines = Hash(Key, Array(String)).new
  @targets = Hash(Key, Array(Endpoint)).new
  # Plain-reference handler text -> the body it names (no one-hop calls).
  @handlers = Hash(String, Key).new
  # Plain-reference handler text -> the definition it names.
  @handler_bodies = Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
  @declared : Hash(String, Set(String))? = nil
  # `name` -> {package, type} for `name := pkg.T{...}` and the like.
  @qualified_types = Hash(String, Set({String, String})).new
  @receivers = Hash(String, Array(Tuple(Noir::GoCalleeExtractor::FunctionBody, String?, String))).new
  # `.Use` / group middleware each route runs behind, see
  # `TreeSitterGoRouteExtractor#route_middleware`.
  @middleware = Hash(Tuple(Int32, String), Array(String)).new
  # Wrapped handler text -> the definition it answers with.
  @resolved = Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
  # Wrapped handler text -> the reference it answers with (`a.UpdateNote`).
  @handler_names = Hash(String, String).new
  # Handler text -> the row of the closure its factory returns.
  @closure_rows = Hash(String, Int32).new
  # {route row, handler name} -> the call a local of the registering
  # function is bound to (`probe := newProbe(store)` then `Handle(p, probe)`).
  @bound = Hash({Int32, String}, String).new
  # Rows of routes whose handler is a call to a function that registers
  # routes itself (`mux.Handle("/v1/", api.NewHandler())`): a mount.
  @mounts = Set(Int32).new

  # `listA` -> {"", "listA"}, `h.List` -> {"h", "List"}, `RateLimit()` ->
  # {"", "RateLimit"}. Anything else (closures, calls with arguments,
  # wrapped handlers) is not a plain reference, so nil.
  def self.reference(handler : String) : Tuple(String, String)?
    if m = handler.match(REFERENCE_RE)
      {m[1].gsub(/\s+/, "").rchop('.'), m[2]}
    end
  end

  @source_lines : Array(String)? = nil

  # `handler_first`: the handler is the first argument after the path and
  # middleware follows it (Echo's `GET(path, h, m...)`), not the last.
  def initialize(@content : String, @path : String, routes : Array(Noir::TreeSitterGoRouteExtractor::Route), scope : Scope? = nil, @handler_first : Bool = false)
    content = @content
    path = @path
    return if routes.empty?
    @middleware = Noir::TreeSitterGoRouteExtractor.route_middleware(content, routes)
    references = Hash(String, Tuple(String, String)).new
    wrapped = Set(String).new
    routes.each do |r|
      if (name = primary_arg(r)) && name.matches?(/\A[A-Za-z_]\w*\z/) && (expr = local_binding_expr(name, r.line))
        @bound[{r.line, name}] = expr
      end
      handler_args(r).each do |h|
        if read = LIBRARY_READS.find { |re, _| h.strip.matches?(re) }
          key = {h.strip, -1}
          @lines[key] = [read[1]]
          @refs[h.strip] = [key]
        elsif ref = self.class.reference(h)
          references[h.strip] = ref
        else
          wrapped << h.strip
        end
      end
    end

    functions = Noir::GoCalleeExtractor.collect_function_bodies(content, path)
    methods = Noir::GoCalleeExtractor.collect_method_bodies(content, path)
    route_rows = routes.map(&.line).sort!
    aliases = Hash(String, String).new
    aliases_read = false
    spans = Hash(Int32, Range(Int32, Int32)).new
    dir = File.dirname(path)
    span_of = ->(fb : Noir::GoCalleeExtractor::FunctionBody) do
      spans[fb.start_row] ||= fb.start_row..(fb.start_row + fb.source.count('\n'))
    end
    registers_routes = ->(fb : Noir::GoCalleeExtractor::FunctionBody) do
      if fb.file_path == path
        span = span_of.call(fb)
        first = route_rows.bsearch { |row| row >= span.begin }
        !!(first && first <= span.end)
      else
        lines = @lines[{fb.file_path, fb.start_row}] ||= Noir::CComments.strip(fb.source, raw_quotes: "`", leak_unterminated_tail: true).lines
        lines.any?(&.matches?(ROUTE_CALL_RE))
      end
    end
    # A plain function name in this file or, given a scope, its package.
    function_named = ->(name : String, in_dir : String) do
      in_dir == dir ? (functions[name]? || scope.try(&.bodies.functions_for(dir)[name]?)) : scope.try(&.bodies.functions_for(in_dir)[name]?)
    end
    # The bodies `names` resolve to, minus route registrars and `skip`.
    keys_for = ->(names : Array(String), in_dir : String, skip : Key?) do
      names.compact_map do |name|
        fb = function_named.call(name, in_dir)
        next unless fb
        key = {fb.file_path, fb.start_row}
        key unless key == skip || registers_routes.call(fb)
      end
    end

    wrapped.each do |handler|
      keys = keys_for.call(handler.scan(NAME_RE).map(&.[0]).uniq!, dir, nil)
      @refs[handler] = keys.uniq unless keys.empty?
    end

    # The definition a plain reference names, or nil.
    resolve = ->(qualifier : String, name : String) do
      if qualifier.empty?
        functions[name]? || scope.try(&.bodies.functions_for(dir)[name]?)
      elsif !qualifier.includes?('.')
        unless aliases_read
          aliases.merge!(Noir::GoCalleeExtractor.extract_import_aliases(content))
          aliases_read = true
        end
        if import_path = aliases[qualifier]?
          if scope && (import_dir = scope.import_dirs[import_path]?)
            scope.bodies.functions_for(import_dir)[name]?
          end
        else
          methods[name]?.try { |candidates| method_for(qualifier, name, candidates, content, "file") } ||
          scope.try(&.bodies.methods_for(dir)[name]?).try { |candidates| method_for(qualifier, name, candidates, content, "package") } ||
          scope.try { |sc| imported_method(qualifier, name, content, aliases, sc) }
        end
      end
    end

    routes.each do |r|
      text = primary_arg(r).try { |arg| @bound[{r.line, arg}]? || arg } || next
      call = factory_call(text.gsub(STRING_LITERAL, %(""))) || next
      qualifier, _, name = call.rpartition('.')
      body = resolve.call(qualifier, name)
      @mounts << r.line if body && registers_routes.call(body)
    end

    # A wrapped handler (`pm(hasID(a.UpdateSubscriber), perm)`,
    # `mw.Gzip()(h.Export)`) answers with the one function value it hands
    # in: a reference that is not called and whose definition is a handler,
    # not another wrapper (see `HANDLER_RESULT`).
    wrapped.each do |handler|
      next if handler.matches?(CLOSURE_ARG)
      found = handler.gsub(STRING_LITERAL, %("")).scan(VALUE_REF_RE).compact_map do |m|
        ref = m[1].gsub(/\s+/, "")
        qualifier, _, name = ref.rpartition('.')
        body = resolve.call(qualifier, name)
        {body, ref} if body && !registers_routes.call(body) && handler_definition?(body)
      end.uniq!(&.[0])
      text = handler.gsub(STRING_LITERAL, %(""))
      # A middleware applied to the handler (`mw(store)(newHandler(store))`)
      # answers with what it is applied to.
      # A wrapper around a factory call (`auth(handleRun(svc))`) answers
      # with what the inner factory builds, tried before the wrapper itself.
      3.times do
        break unless found.empty?
        inner = applied_arg(text) || wrapped_call_arg(text)
        {inner, text}.each do |candidate|
          next unless candidate && found.empty?
          next unless call = factory_call(candidate)
          # A handler factory called with arguments (`serveFile("a.html",
          # "text/html")`) answers with the closure it returns, or with the
          # method value it returns (`return http.HandlerFunc(h.serve)`).
          qualifier, _, name = call.rpartition('.')
          body = resolve.call(qualifier, name)
          next if body.nil? || registers_routes.call(body)
          if returned_closure_row(body)
            found << {body, call}
          elsif (method = returned_method(body, scope)) && !registers_routes.call(method[0])
            found << method
          end
        end
        text = inner || break
      end
      next unless found.size == 1
      @resolved[handler], @handler_names[handler] = found.first
      references[handler] = {"", ""}
    end

    references.each do |handler, (qualifier, name)|
      body = @resolved[handler]? || resolve.call(qualifier, name)
      # A function that registers routes itself is never claimed.
      next if body.nil? || registers_routes.call(body)
      # A factory called with no arguments that returns a handler method
      # value (`fever.NewHandler()` returning `http.HandlerFunc(h.serve)`)
      # answers with that method.
      if handler.ends_with?(')') && !@resolved.has_key?(handler) && (method = returned_method(body, scope))
        body, @handler_names[handler] = method
      end

      key = {body.file_path, body.start_row}
      @handlers[handler] = key
      @handler_bodies[handler] = body
      returned_closure_row(body).try { |row| @closure_rows[handler] = row }
      # One hop further: the functions the handler body calls.
      calls = body.source.scan(CALL_RE).map(&.[1]).uniq!
      keys = (@refs[handler]? || [] of Key).concat([key]).concat(keys_for.call(calls, File.dirname(body.file_path), key))
      # ... and the methods it calls on its own receiver (`a.doReset(c)` in
      # `func (a *App) ResetPage(c)`), matched by receiver type.
      if (recv = body.source.match(RECEIVER_RE)) && (recv_name = recv[1]?)
        table = scope.try(&.bodies.methods_for(File.dirname(body.file_path))) || (body.file_path == path ? methods : nil)
        body.source.scan(RECEIVER_CALL_RE).each do |m|
          next unless m[1] == recv_name && (candidates = table.try(&.[m[2]]?))
          found = candidates.select { |fb| fb.source.match(RECEIVER_RE).try(&.[2]) == recv[2] }
          next unless found.size == 1
          next if registers_routes.call(found.first)
          keys << {found.first.file_path, found.first.start_row}
        end
      end
      @refs[handler] = keys.uniq
    end

    # Every route-free body in this file is claimed, bound or not.
    functions.each_value.chain(methods.each_value.flat_map(&.itself)).each do |fb|
      next if registers_routes.call(fb)
      key = {path, fb.start_row}
      span_of.call(fb).each { |row| @rows[row] = key }
    end
  end

  # The handler argument that answers: the last, or the first with
  # `handler_first`.
  private def primary_arg(route : Noir::TreeSitterGoRouteExtractor::Route) : String?
    (@handler_first ? route.handler_args.first? : route.handler_args.last?).try(&.strip)
  end

  # The handler a function application hands in: `B(y)` in `A(x)(B(y))`.
  # Nil unless the text ends in a call of a call with one argument.
  private def applied_arg(text : String) : String?
    text = text.strip
    return unless text.ends_with?(')')
    depth = 0
    (text.size - 1).downto(0) do |pos|
      case text[pos]
      when ')' then depth += 1
      when '('
        depth -= 1
        next unless depth.zero?
        return unless pos > 0 && text[0, pos].rstrip.ends_with?(')')
        inner = text[pos + 1...-1].strip
        return if inner.empty? || Noir::TopLevelSplit.split(inner, ',', Noir::TopLevelSplit::Rules.new).size != 1
        return inner
      end
    end
  end

  # The one argument of a call that is itself a call: `handleRun(svc)` in
  # `auth(handleRun(svc))`. Nil for anything else.
  private def wrapped_call_arg(text : String) : String?
    factory_call(text) || return
    open = text.index('(') || return
    args = Noir::TopLevelSplit.split(text[open + 1...-1], ',', Noir::TopLevelSplit::Rules.new)
    return unless args.size == 1
    arg = args.first.strip
    arg if factory_call(arg)
  end

  RETURNED_VALUE = /\A\s*return\s+(?:(?:http\s*\.\s*)?HandlerFunc\s*\(\s*)?([A-Za-z_]\w*)\s*\.\s*([A-Za-z_]\w*)\s*\)?\s*\z/

  # The handler method a factory returns as a value (`h := &T{...}` then
  # `return http.HandlerFunc(h.serve)`): the one method `serve` on the type
  # the body declares `h` with, in the factory's package. Nil when the body
  # returns anything else, or several values.
  private def returned_method(body : Noir::GoCalleeExtractor::FunctionBody, scope : Scope?) : Tuple(Noir::GoCalleeExtractor::FunctionBody, String)?
    scope || return
    refs = body.source.lines.compact_map(&.match(RETURNED_VALUE))
    return unless refs.size == 1
    receiver, name = refs.first[1], refs.first[2]
    types = Set(String).new
    {ASSIGNED_TYPE_RE, NEW_TYPE_RE}.each do |re|
      body.source.scan(re) { |m| types << m[3] if m[1] == receiver && m[2]?.nil? }
    end
    return if types.size != 1
    candidates = scope.bodies.methods_for(File.dirname(body.file_path))[name]? || return
    found = candidates.select { |fb| fb.source.match(RECEIVER_RE).try(&.[2]) == types.first }
    return unless found.size == 1 && handler_definition?(found.first)
    {found.first, "#{receiver}.#{name}"}
  end

  # The call expression a local named `name` is bound to above `row`, in
  # the top-level function that holds `row` (`probe := newProbe(store)`).
  # Nil for a closure (see `local_closure_row`) or a statement that does not
  # end on its line.
  # ponytail: line-based like `local_closure_row`.
  private def local_binding_expr(name : String, row : Int32) : String?
    lines = @source_lines ||= @content.lines
    (row - 1).downto(0) do |idx|
      line = lines[idx]? || next
      return if line.starts_with?("func ") || line.starts_with?("func(")
      code = line.strip
      next unless code.starts_with?(name)
      rest = code[name.size..].lstrip
      next if !rest.starts_with?(":=") && (!rest.starts_with?('=') || rest.starts_with?("=="))
      expr = rest.lchop(":=").lchop('=').strip
      return if expr.matches?(CLOSURE_HANDLER) || !expr.matches?(/\A[\w.]+\s*\(/)
      return unless expr.count('(') == expr.count(')') && expr.ends_with?(')')
      return expr
    end
  end

  # The callee of a handler argument that is one call and nothing else
  # (`serveFile("a", b)`, `h.Page("x")`), or nil.
  private def factory_call(handler : String) : String?
    m = handler.match(/\A((?:[A-Za-z_]\w*\s*\.\s*)*[A-Za-z_]\w*)\s*\(/) || return
    depth = 0
    (m.end - 1...handler.size).each do |pos|
      char = handler[pos]
      depth += 1 if char == '('
      next unless char == ')'
      depth -= 1
      return pos == handler.size - 1 ? m[1].gsub(/\s+/, "") : nil if depth.zero?
    end
  end

  RETURNED_CLOSURE = /\A\s*return\s+func\s*\(/

  # The row of the one closure a handler factory returns (`func serveFile(
  # ...) gin.HandlerFunc { ...; return func(ctx *gin.Context) {...} }`):
  # that closure serves the request. Nil for a handler itself, or a body
  # that returns no closure or several.
  private def returned_closure_row(body : Noir::GoCalleeExtractor::FunctionBody) : Int32?
    return if handler_definition?(body)
    row = nil
    body.source.each_line.with_index do |line, idx|
      next unless line.matches?(RETURNED_CLOSURE)
      return if row
      row = body.start_row + idx
    end
    row
  end

  # Whether `body` is declared as a handler: it takes parameters and
  # returns nothing or an `error` (see `HANDLER_RESULT`).
  private def handler_definition?(body : Noir::GoCalleeExtractor::FunctionBody) : Bool
    source = body.source
    groups = source.lstrip.lchop("func").lstrip.starts_with?('(') ? 2 : 1
    depth = 0
    seen = 0
    open = 0
    source.each_char_with_index do |char, pos|
      if char == '('
        open = pos if depth.zero?
        depth += 1
      elsif char == ')'
        depth -= 1
        next unless depth.zero?
        seen += 1
        next unless seen == groups
        return !source[open + 1...pos].blank? && source[pos + 1, 32].matches?(HANDLER_RESULT)
      end
    end
    false
  end

  # The one method in `candidates` the selector `qualifier.Name` can mean.
  # `table` names the candidate list (this file's or the package's) for
  # the receiver memo.
  private def method_for(qualifier : String,
                         name : String,
                         candidates : Array(Noir::GoCalleeExtractor::FunctionBody),
                         content : String,
                         table : String) : Noir::GoCalleeExtractor::FunctionBody?
    receivers = @receivers["#{table}:#{name}"] ||= candidates.compact_map do |fb|
      if m = fb.source.match(RECEIVER_RE)
        {fb, m[1]?, m[2]}
      end
    end
    types = declared_types(qualifier, content)
    found = nil
    receivers.each do |fb, recv_name, recv_type|
      next unless types.empty? ? recv_name == qualifier : types.includes?(recv_type)
      return if found
      found = fb
    end
    found
  end

  # The method `name` of the struct a local value is declared with when that
  # type lives in an imported package (`h := api.UserAPI{...}` then
  # `h.Create` -> `func (a *UserAPI) Create` in the package `api` names).
  # Nil unless exactly one definition matches.
  private def imported_method(qualifier : String, name : String, content : String,
                              aliases : Hash(String, String), scope : Scope) : Noir::GoCalleeExtractor::FunctionBody?
    declared_types(qualifier, content)
    found = nil
    @qualified_types[qualifier]?.try &.each do |(package, type)|
      import_dir = aliases[package]?.try { |import_path| scope.import_dirs[import_path]? } || next
      scope.bodies.methods_for(import_dir)[name]?.try &.each do |fb|
        next unless fb.source.match(RECEIVER_RE).try(&.[2]) == type
        return if found && found != fb
        found = fb
      end
    end
    found
  end

  # Type names `name` is declared with in this file: `name := &T{}`,
  # `var name = T{}`, `name := new(T)`, `name *T` (parameter, field or
  # `var`), and a method receiver `(name *T)`. Empty when none is visible.
  # The whole file is indexed on first use, so each lookup is O(1).
  private def declared_types(name : String, content : String) : Set(String)
    declared = @declared ||= begin
      index = Hash(String, Set(String)).new
      {ASSIGNED_TYPE_RE, NEW_TYPE_RE, DECLARED_TYPE_RE}.each do |re|
        content.scan(re) do |m|
          (index[m[1]] ||= Set(String).new) << m[3]
          (@qualified_types[m[1]] ||= Set({String, String}).new) << {m[2], m[3]} if m[2]?
        end
      end
      index
    end
    declared[name]? || Set(String).new
  end

  # True when `line` (0-based `index`) is inside the body of a function a
  # route names; the line is held for `each_attribution`.
  def claim?(index : Int32, line : String) : Bool
    return false unless key = @rows[index]?
    (@lines[key] ||= [] of String) << line
    true
  end

  # The route's handler resolved to its definition: the *last* handler
  # argument, which is the one that answers (everything before it is
  # middleware), or the first one with `handler_first`. A wrapped handler
  # names the function value it hands in. An inline closure there is the handler, named `closure` at
  # the line it starts on; a middleware before a closure is never promoted,
  # since `route.GET("/home", CookieTool(), func(c) {...})` is not handled
  # by CookieTool. A bare name bound to a closure in the registering
  # function (`isLive := func(c *gin.Context) {...}`) names that closure.
  # The definition the route's handler resolves to (see `handler_for`), for
  # reading its request params; nil for an inline closure.
  def handler_body(route : Noir::TreeSitterGoRouteExtractor::Route) : Noir::GoCalleeExtractor::FunctionBody?
    name = primary_arg(route) || return
    @handler_bodies[@bound[{route.line, name}]? || name]?
  end

  def handler_for(route : Noir::TreeSitterGoRouteExtractor::Route) : Handler?
    name = primary_arg(route) || return
    name = @bound[{route.line, name}]? || name
    if name.matches?(CLOSURE_HANDLER)
      row = route.handler_row || return
      return Handler.new("closure", @path, row + 1)
    end
    if key = @handlers[name]?
      return Handler.new(@handler_names[name]? || name, key[0], (@closure_rows[name]? || key[1]) + 1)
    end
    if name.matches?(/\A[A-Za-z_]\w*\z/) && (row = local_closure_row(name, route.line))
      Handler.new(name, @path, row + 1)
    end
  end

  CLOSURE_HANDLER = /\A\s*func\s*\(/

  # The row of the nearest `name := func(` / `name = func(` above `row`,
  # searched back to the head of the top-level function that holds `row`.
  # ponytail: line-based; a closure rebound in a nested block above the
  # route still reads as the nearest binding.
  private def local_closure_row(name : String, row : Int32) : Int32?
    lines = @source_lines ||= @content.lines
    (row - 1).downto(0) do |idx|
      line = lines[idx]? || next
      return if line.starts_with?("func ") || line.starts_with?("func(")
      code = line.lstrip
      next unless code.starts_with?(name)
      rest = code[name.size..].lstrip.lchop(':')
      return idx if rest.starts_with?('=') && rest[1..].matches?(CLOSURE_HANDLER)
    end
  end

  # Whether the route hands its path to a router a called function builds
  # (`mux.Handle("/v1/", api.NewHandler(store))`): that router's own routes
  # are reported, so the mount is not a route.
  def mount?(route : Noir::TreeSitterGoRouteExtractor::Route) : Bool
    @mounts.includes?(route.line)
  end

  def bind(route : Noir::TreeSitterGoRouteExtractor::Route, endpoint : Endpoint)
    return if @refs.empty?
    handler_args(route).flat_map { |handler| @refs[handler.strip]? || [] of Key }.uniq!.each do |key|
      (@targets[key] ||= [] of Endpoint) << endpoint
    end
  end

  # The route's handler args behind the middleware it runs after.
  private def handler_args(route : Noir::TreeSitterGoRouteExtractor::Route) : Array(String)
    args = route.handler_args.map { |arg| @bound[{route.line, arg.strip}]? || arg }
    mw = @middleware[{route.line, route.router_name}]?
    mw ? mw + args : args
  end

  # Yields each bound body's file and lines with the endpoints routed to it.
  def each_bound_body(& : String, Array(String), Array(Endpoint) ->)
    @lines.each do |key, lines|
      eps = @targets[key]?
      yield key[0], lines, eps if eps
    end
  end

  # Yields every claimed line with each endpoint routed to its handler.
  def each_attribution(& : String, Endpoint ->)
    @lines.each do |key, lines|
      next unless eps = @targets[key]?
      lines.each { |line| eps.each { |ep| yield line, ep } }
    end
  end
end
