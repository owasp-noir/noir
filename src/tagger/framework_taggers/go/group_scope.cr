require "../prefix_scope"

# Shared Go route-group scope resolution for the Go framework taggers.
#
# Both `go_auth` and `go_security` answer the same question: a middleware
# registration (`x.Use(...)`) appears on some line — which URL prefix does it
# guard? Go routers express grouping two structurally different ways, and they
# have to be tracked differently:
#
#   * assignment groups — `api := r.Group("/api")`. The variable carries the
#     prefix; the group is NOT delimited by braces, so `api.Use(...)` may sit
#     anywhere below, and a sibling `admin := r.Group("/admin")` is a separate
#     scope, not a nested one.
#   * closure groups — `r.Route("/api", func(r chi.Router) { ... })`. The
#     prefix applies to everything inside the closure, so it is delimited by
#     brace depth.
#
# Modelling both with a single push/pop stack makes sibling assignment groups
# *accumulate*: `/api` then `/admin` resolves the second group's middleware to
# `/api/admin`. That is both a false negative (the real `/admin/*` routes lose
# their tag) and — worse for a security tool — a false positive (`/api/admin/*`
# routes are reported as guarded when they are not).
#
# The third case is a group whose path is not a string literal
# (`r.Group(cfg.APIBase + "/v1")`). Its prefix is genuinely unknowable to a
# line-based scanner, and it must NOT collapse to "global": a real app that
# builds every group that way would have every endpoint — including its
# explicitly public ones — tagged from whichever `.Use(auth)` happened to be
# scanned first. `Unknown` keeps that case distinguishable from `Global` so
# callers can decline to tag, matching `spring_security`'s treatment of a
# filter chain scoped only by a matcher it cannot resolve.
module GoRouteGroupScope
  # `prefix_covers?` — the segment-aware match a resolved group prefix is
  # tested with. Shared with the Express and Ktor taggers, which used to
  # compare with a bare `starts_with?`.
  include PrefixScope

  # What a receiver / middleware registration resolves to.
  #
  #   Global  — no enclosing group; an engine-level `.Use` guards everything
  #             registered after it.
  #   Group   — a route group whose URL prefix is known.
  #   Unknown — a route group whose URL prefix could not be resolved.
  enum ScopeKind
    Global
    Group
    Unknown
  end

  alias Scope = NamedTuple(kind: ScopeKind, prefix: String)

  GLOBAL_SCOPE  = {kind: ScopeKind::Global, prefix: "/"}
  UNKNOWN_SCOPE = {kind: ScopeKind::Unknown, prefix: "/"}

  # `name := parent.Group("/seg")` — assignment group with a literal path.
  ASSIGN_GROUP = /(\w+)\s*:?=\s*(\w+)\.(?:Group|Route|Party|PartyFunc)\s*\(\s*"([^"]*)"/

  # The same assignment shape with *any* first argument, literal or not. Used
  # to tell "this variable is a route group whose prefix we can't read" from
  # "this variable is not a route group at all".
  ASSIGN_GROUP_ANY = /(\w+)\s*:?=\s*(\w+)\.(?:Group|Route|Party|PartyFunc)\s*\(/

  # `parent.Group("/seg", func(...)` / `.Route` / `.Party` closure group.
  CLOSURE_GROUP     = /(\w+)\.(?:Group|Route|Party|PartyFunc|Mount)\s*\(\s*"([^"]*)"\s*,\s*func/
  CLOSURE_GROUP_ANY = /(\w+)\.(?:Group|Route|Party|PartyFunc|Mount)\s*\(.*\bfunc\b/

  # A `.Use(...)` / `.Pre(...)` middleware registration call.
  USE_CALL = /(\w+)\.(?:Use|Pre)\s*\(/

  # `r.Group("/api").Use(auth)` — the group is created and the middleware
  # registered in one chained expression, so it is neither an assignment nor a
  # closure group. `USE_CALL` cannot see the receiver here (the character
  # before `.Use` is `)`), so match the chain directly.
  CHAINED_GROUP_USE     = /(\w+)\.(?:Group|Route|Party|PartyFunc)\s*\(\s*"([^"]*)"\s*\)\s*\.\s*(?:Use|Pre)\s*\(/
  CHAINED_GROUP_USE_ANY = /(\w+)\.(?:Group|Route|Party|PartyFunc)\s*\([^)]*\)\s*\.\s*(?:Use|Pre)\s*\(/

  # The route-group state at one point in a file: the assignment-group table
  # and the stack of closure groups still open at the current brace depth.
  class Scopes
    # Variable name -> the scope it names.
    getter groups = {} of String => Scope
    # Open closure groups, each with the brace depth it lives above.
    getter frames = [] of NamedTuple(threshold: Int32, scope: Scope)

    # The innermost enclosing closure group, or Global at file scope.
    def current : Scope
      frames.empty? ? GLOBAL_SCOPE : frames.last[:scope]
    end

    # Resolve a receiver token: a tracked group variable, the innermost open
    # closure group, or the global scope.
    def receiver(name : String?) : Scope
      return current if name.nil?
      groups[name]? || current
    end

    # `base` extended by one path segment. An unresolvable base stays
    # unresolvable — a literal segment under an unknown parent is still
    # unknown.
    def extend(base : Scope, seg : String) : Scope
      return UNKNOWN_SCOPE if base.[:kind] == ScopeKind::Unknown
      {kind: ScopeKind::Group, prefix: GoRouteGroupScope.join_prefix(base[:prefix], seg)}
    end
  end

  # Walk `content` line by line, maintaining the route-group state, and yield
  # each stripped line alongside it. Callers resolve a middleware registration
  # with `resolve_use_scope`.
  def each_group_scoped_line(content : String, &) : Nil
    scopes = Scopes.new
    depth = 0

    content.each_line do |line|
      stripped = line.strip

      # Resolve both group forms against the scope state as it stood *before*
      # this line. One line can be both — `admin := r.Group("/admin", func(c
      # *gin.Context) {...})` is a closure group whose value is also assigned —
      # and resolving the assignment after pushing the closure frame would fold
      # the line's own prefix in twice (`/admin/admin`), so `admin.Use(auth)`
      # below would guard nothing.
      closure_scope =
        if m = stripped.match(CLOSURE_GROUP)
          scopes.extend(scopes.receiver(m[1]), m[2])
        elsif stripped.matches?(CLOSURE_GROUP_ANY)
          UNKNOWN_SCOPE
        end

      assigned =
        if m = stripped.match(ASSIGN_GROUP)
          {m[1], scopes.extend(scopes.receiver(m[2]), m[3])}
        elsif m = stripped.match(ASSIGN_GROUP_ANY)
          {m[1], UNKNOWN_SCOPE}
        end

      # Closure group: its prefix stays active until braces unwind.
      scopes.frames << {threshold: depth, scope: closure_scope} if closure_scope
      # Assignment group: remember the variable's scope for later `.Use`.
      scopes.groups[assigned[0]] = assigned[1] if assigned

      yield stripped, scopes

      # Update brace depth and retire any closure scopes that just closed.
      depth += line.count('{') - line.count('}')
      while !scopes.frames.empty? && depth <= scopes.frames.last[:threshold]
        scopes.frames.pop
      end
    end
  end

  # The scope a middleware registration on `stripped` guards, or nil when the
  # line registers no middleware. Callers must decline to tag an `Unknown`
  # scope rather than treating it as global.
  def resolve_use_scope(stripped : String, scopes : Scopes) : Scope?
    if m = stripped.match(CHAINED_GROUP_USE)
      return scopes.extend(scopes.receiver(m[1]), m[2])
    end
    return UNKNOWN_SCOPE if stripped.matches?(CHAINED_GROUP_USE_ANY)

    receiver = stripped.match(USE_CALL).try &.[1]
    return if receiver.nil?

    scopes.receiver(receiver)
  end

  # Join a base prefix and a new path segment into a normalized URL prefix:
  #   ("", "/web") -> "/web"   ("/api", "v1") -> "/api/v1"
  def self.join_prefix(base : String, seg : String) : String
    parts = "#{base}/#{seg}".split("/").reject(&.empty?)
    parts.empty? ? "/" : "/" + parts.join("/")
  end
end
