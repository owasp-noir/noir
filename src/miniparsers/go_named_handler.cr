require "../models/endpoint"
require "./go_callee_extractor"
require "./go_route_extractor_ts"

# Same-file named-handler attribution for the Go adapters' line loops.
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
#   * a function that registers routes itself is never claimed.
class Noir::GoNamedHandler
  RECEIVER_RE  = /\Afunc\s*\(\s*(?:([A-Za-z_]\w*)\s+)?\*?\s*([A-Za-z_]\w*)/
  REFERENCE_RE = /\A\s*((?:[A-Za-z_]\w*\s*\.\s*)*)([A-Za-z_]\w*)\s*(?:\(\s*\))?\s*\z/

  # Declarations that pin a name's type, scanned once per file (see
  # `declared_types`). Assignments are anchored at a statement start, so the
  # second name of `a, b := &X{}, newY()` is never typed `X`.
  ASSIGNED_TYPE_RE = /(?:\A|[\n;{(])[ \t]*(?:var[ \t]+)?([A-Za-z_]\w*)[ \t]*:?=[ \t]*(?:&[ \t]*)?(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)[ \t]*\{/
  NEW_TYPE_RE      = /(?:\A|[\n;{(])[ \t]*(?:var[ \t]+)?([A-Za-z_]\w*)[ \t]*:?=[ \t]*new\([ \t]*(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)[ \t]*\)/
  # `name *T` as a parameter, receiver, struct field or `var`.
  DECLARED_TYPE_RE = /(?:\A|[\n(,]|\bvar)[ \t]*([A-Za-z_]\w*)[ \t]+\*?(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)/

  @rows = Hash(Int32, Int32).new
  @refs = Hash(String, Int32).new
  @lines = Hash(Int32, Array(String)).new
  @targets = Hash(Int32, Array(Endpoint)).new
  @declared : Hash(String, Set(String))? = nil
  @receivers = Hash(String, Array(Tuple(Noir::GoCalleeExtractor::FunctionBody, String?, String))).new

  # `listA` -> {"", "listA"}, `h.List` -> {"h", "List"}, `RateLimit()` ->
  # {"", "RateLimit"}. Anything else (closures, calls with arguments,
  # wrapped handlers) is not a plain reference, so nil.
  def self.reference(handler : String) : Tuple(String, String)?
    if m = handler.match(REFERENCE_RE)
      {m[1].gsub(/\s+/, "").rchop('.'), m[2]}
    end
  end

  def initialize(content : String, path : String, routes : Array(Noir::TreeSitterGoRouteExtractor::Route))
    references = Hash(String, Tuple(String, String)).new
    routes.each do |r|
      r.handler_args.each do |h|
        if ref = self.class.reference(h)
          references[h.strip] = ref
        end
      end
    end
    return if references.empty?

    functions = Noir::GoCalleeExtractor.collect_function_bodies(content, path)
    methods = Noir::GoCalleeExtractor.collect_method_bodies(content, path)
    route_rows = routes.map(&.line).sort!
    imports = nil
    spans = Hash(Int32, Range(Int32, Int32)).new

    references.each do |handler, (qualifier, name)|
      body = if qualifier.empty?
               functions[name]?
             elsif (candidates = methods[name]?) && !qualifier.includes?('.')
               imports ||= Noir::GoCalleeExtractor.extract_import_aliases(content)
               method_for(qualifier, name, candidates, content) unless imports.has_key?(qualifier)
             end
      next unless body

      span = spans[body.start_row] ||= body.start_row..(body.start_row + body.source.count('\n'))
      # A function that registers routes itself is never claimed.
      first = route_rows.bsearch { |row| row >= span.begin }
      next if first && first <= span.end
      @refs[handler] = body.start_row
    end

    @refs.each_value { |start| spans[start].each { |row| @rows[row] = start } }
  end

  # The one method in `candidates` the selector `qualifier.Name` can mean.
  private def method_for(qualifier : String,
                         name : String,
                         candidates : Array(Noir::GoCalleeExtractor::FunctionBody),
                         content : String) : Noir::GoCalleeExtractor::FunctionBody?
    receivers = @receivers[name] ||= candidates.compact_map do |fb|
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
    return false unless start = @rows[index]?
    (@lines[start] ||= [] of String) << line
    true
  end

  def bind(route : Noir::TreeSitterGoRouteExtractor::Route, endpoint : Endpoint)
    return if @refs.empty?
    route.handler_args.compact_map { |handler| @refs[handler.strip]? }.uniq!.each do |start|
      (@targets[start] ||= [] of Endpoint) << endpoint
    end
  end

  # Yields every claimed line with each endpoint routed to its handler.
  def each_attribution(& : String, Endpoint ->)
    @lines.each do |start, lines|
      next unless eps = @targets[start]?
      lines.each { |line| eps.each { |ep| yield line, ep } }
    end
  end
end
