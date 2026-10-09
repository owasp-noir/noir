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
  RECEIVER_RE = /\Afunc\s*\(\s*(?:([A-Za-z_]\w*)\s+)?\*?\s*([A-Za-z_]\w*)/

  @rows = Hash(Int32, Int32).new
  @refs = Hash(String, Int32).new
  @lines = Hash(Int32, Array(String)).new
  @targets = Hash(Int32, Array(Endpoint)).new

  # `listA` -> {"", "listA"}, `h.List` -> {"h", "List"}, `RateLimit()` ->
  # {"", "RateLimit"}. Anything else (closures, calls with arguments,
  # wrapped handlers) is not a plain reference, so nil.
  def self.reference(handler : String) : Tuple(String, String)?
    if m = handler.match(/\A\s*((?:[A-Za-z_]\w*\s*\.\s*)*)([A-Za-z_]\w*)\s*(?:\(\s*\))?\s*\z/)
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
    route_rows = routes.map(&.line)
    imports = nil
    spans = Hash(Int32, Range(Int32, Int32)).new

    references.each do |handler, (qualifier, name)|
      body = if qualifier.empty?
               functions[name]?
             elsif (candidates = methods[name]?) && !qualifier.includes?('.')
               imports ||= Noir::GoCalleeExtractor.extract_import_aliases(content)
               method_for(qualifier, candidates, content) unless imports.has_key?(qualifier)
             end
      next unless body

      span = spans[body.start_row] ||= body.start_row..(body.start_row + body.source.count('\n'))
      next if route_rows.any? { |row| span.includes?(row) }
      @refs[handler] = body.start_row
    end

    @refs.each_value { |start| spans[start].each { |row| @rows[row] = start } }
  end

  # The one method in `candidates` the selector `qualifier.Name` can mean.
  private def method_for(qualifier : String,
                         candidates : Array(Noir::GoCalleeExtractor::FunctionBody),
                         content : String) : Noir::GoCalleeExtractor::FunctionBody?
    receivers = candidates.compact_map do |fb|
      if m = fb.source.match(RECEIVER_RE)
        {fb, m[1]?, m[2]}
      end
    end
    types = declared_types(qualifier, content)
    matches = if types.empty?
                receivers.select { |_, recv_name, _| recv_name == qualifier }
              else
                receivers.select { |_, _, recv_type| types.includes?(recv_type) }
              end
    matches.size == 1 ? matches.first[0] : nil
  end

  # Type names `name` is declared with in this file: `name := &T{}`,
  # `var name = T{}`, `name := new(T)`, `name *T` (parameter, field or
  # `var`), and a method receiver `(name *T)`. Empty when none is visible.
  private def declared_types(name : String, content : String) : Set(String)
    types = Set(String).new
    n = Regex.escape(name)
    content.scan(/\b#{n}\s*:?=\s*&?\s*(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)\s*\{/) { |m| types << m[1] }
    content.scan(/\b#{n}\s*:?=\s*new\(\s*(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)\s*\)/) { |m| types << m[1] }
    content.scan(/(?:^|[(,]|\bvar)[ \t]*#{n}[ \t]+\*?(?:[A-Za-z_]\w*\.)?([A-Za-z_]\w*)/m) { |m| types << m[1] }
    types
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
