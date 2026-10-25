require "../models/endpoint"
require "../utils/c_comments"
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
  ASSIGNED_TYPE_RE = /(?:\A|[\n;{(])[ \t]*(?:var[ \t]+)?([A-Za-z_]\w*)[ \t]*:?=[ \t]*(?:&[ \t]*)?(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)[ \t]*\{/
  NEW_TYPE_RE      = /(?:\A|[\n;{(])[ \t]*(?:var[ \t]+)?([A-Za-z_]\w*)[ \t]*:?=[ \t]*new\([ \t]*(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)[ \t]*\)/
  # `name *T` as a parameter, receiver, struct field or `var`.
  DECLARED_TYPE_RE = /(?:\A|[\n(,]|\bvar)[ \t]*([A-Za-z_]\w*)[ \t]+\*?(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)/

  # Library middleware whose request read lives in a dependency the scan
  # never sees, with that read as the source line the adapters parse:
  # gin's BasicAuth checks the `Authorization` header.
  LIBRARY_READS = {
    {/\Agin\.BasicAuth(?:ForRealm)?\s*\(/, %(c.Request.Header.Get("Authorization"))},
  }

  # A route registration with a path literal: the stand-in for the
  # same-file route-row check on a body declared in another file.
  ROUTE_CALL_RE = /\.(?:GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS|Get|Post|Put|Delete|Patch|Head|Options|Any|All|Handle|HandleFunc|Group|Route|Mount)\s*\(\s*"\//

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
  @declared : Hash(String, Set(String))? = nil
  @receivers = Hash(String, Array(Tuple(Noir::GoCalleeExtractor::FunctionBody, String?, String))).new
  # `.Use` / group middleware each route runs behind, see
  # `TreeSitterGoRouteExtractor#route_middleware`.
  @middleware = Hash(Tuple(Int32, String), Array(String)).new
  # Wrapped handler text -> the definition it answers with.
  @resolved = Hash(String, Noir::GoCalleeExtractor::FunctionBody).new
  # Wrapped handler text -> the reference it answers with (`a.UpdateNote`).
  @handler_names = Hash(String, String).new

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
          scope.try(&.bodies.methods_for(dir)[name]?).try { |candidates| method_for(qualifier, name, candidates, content, "package") }
        end
      end
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
      next unless found.size == 1
      @resolved[handler], @handler_names[handler] = found.first
      references[handler] = {"", ""}
    end

    references.each do |handler, (qualifier, name)|
      body = @resolved[handler]? || resolve.call(qualifier, name)
      # A function that registers routes itself is never claimed.
      next if body.nil? || registers_routes.call(body)

      key = {body.file_path, body.start_row}
      @handlers[handler] = key
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

  # Type names `name` is declared with in this file: `name := &T{}`,
  # `var name = T{}`, `name := new(T)`, `name *T` (parameter, field or
  # `var`), and a method receiver `(name *T)`. Empty when none is visible.
  # The whole file is indexed on first use, so each lookup is O(1).
  private def declared_types(name : String, content : String) : Set(String)
    declared = @declared ||= begin
      index = Hash(String, Set(String)).new
      {ASSIGNED_TYPE_RE, NEW_TYPE_RE, DECLARED_TYPE_RE}.each do |re|
        content.scan(re) { |m| (index[m[1]] ||= Set(String).new) << m[2] }
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
  def handler_for(route : Noir::TreeSitterGoRouteExtractor::Route) : Handler?
    name = (@handler_first ? route.handler_args.first? : route.handler_args.last?).try(&.strip) || return
    if name.matches?(CLOSURE_HANDLER)
      row = route.handler_row || return
      return Handler.new("closure", @path, row + 1)
    end
    if key = @handlers[name]?
      return Handler.new(@handler_names[name]? || name, key[0], key[1] + 1)
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

  def bind(route : Noir::TreeSitterGoRouteExtractor::Route, endpoint : Endpoint)
    return if @refs.empty?
    handler_args(route).flat_map { |handler| @refs[handler.strip]? || [] of Key }.uniq!.each do |key|
      (@targets[key] ||= [] of Endpoint) << endpoint
    end
  end

  # The route's handler args behind the middleware it runs after.
  private def handler_args(route : Noir::TreeSitterGoRouteExtractor::Route) : Array(String)
    mw = @middleware[{route.line, route.router_name}]?
    mw ? mw + route.handler_args : route.handler_args
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
