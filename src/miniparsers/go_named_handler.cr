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
# endpoint with its route's handler text, then `each_attribution` once the
# loop is done (the handler may be declared above or below its route).
#
# Only unambiguous references are claimed; everything else keeps the legacy
# attribution:
#   * a bare `listA` resolves to the one `func listA` in this file;
#   * a selector `h.List` resolves to the one method `List` in this file,
#     and only when every route naming `List` uses the same receiver text
#     (`u.List` + `p.List` is two controllers) and that receiver is not an
#     imported package (`handlers.List` lives elsewhere);
#   * a function that registers routes itself is never claimed.
class Noir::GoNamedHandler
  @rows = Hash(Int32, String).new
  @lines = Hash(String, Array(String)).new
  @targets = Hash(String, Array(Endpoint)).new

  # `listA` -> {"", "listA"}, `h.List` -> {"h", "List"}. Anything else
  # (closures, wrapped calls) is not a plain reference, so nil.
  def self.reference(handler : String) : Tuple(String, String)?
    if m = handler.match(/\A\s*((?:[A-Za-z_]\w*\s*\.\s*)*)([A-Za-z_]\w*)\s*\z/)
      {m[1].gsub(/\s+/, "").rchop('.'), m[2]}
    end
  end

  def initialize(content : String, path : String, routes : Array(Noir::TreeSitterGoRouteExtractor::Route))
    qualifiers = Hash(String, Set(String)).new
    routes.each do |r|
      next unless ref = self.class.reference(r.handler)
      (qualifiers[ref[1]] ||= Set(String).new) << ref[0]
    end
    return if qualifiers.empty?

    functions = Noir::GoCalleeExtractor.collect_function_bodies(content, path)
    methods = Noir::GoCalleeExtractor.collect_method_bodies(content, path)
    route_rows = routes.map(&.line)
    imports = nil

    qualifiers.each do |name, quals|
      next unless quals.size == 1
      qualifier = quals.first
      body = if qualifier.empty?
               functions[name]?
             elsif (candidates = methods[name]?) && candidates.size == 1
               imports ||= Noir::GoCalleeExtractor.extract_import_aliases(content)
               candidates.first unless imports.has_key?(qualifier.split('.').first)
             end
      next unless body

      span = body.start_row..(body.start_row + body.source.count('\n'))
      next if route_rows.any? { |row| span.includes?(row) }
      span.each { |row| @rows[row] ||= name }
    end
  end

  # True when `line` (0-based `index`) is inside the body of a function a
  # route names; the line is held for `each_attribution`.
  def claim?(index : Int32, line : String) : Bool
    return false unless name = @rows[index]?
    (@lines[name] ||= [] of String) << line
    true
  end

  def bind(handler : String, endpoint : Endpoint)
    return if @rows.empty?
    return unless ref = self.class.reference(handler)
    (@targets[ref[1]] ||= [] of Endpoint) << endpoint
  end

  # Yields every claimed line with each endpoint routed to its handler.
  def each_attribution(& : String, Endpoint ->)
    @lines.each do |name, lines|
      next unless eps = @targets[name]?
      lines.each { |line| eps.each { |ep| yield line, ep } }
    end
  end
end
