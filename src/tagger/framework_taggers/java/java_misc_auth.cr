require "../../../miniparsers/kotlin_source_mask"
require "../../../models/framework_tagger"
require "../../../models/endpoint"
require "../prefix_scope"
require "./java_access"

@[Noir::TaggerFor(key: "java_misc_auth", name: "Java Misc Auth Tagger", desc: "Identifies Vert.x/Armeria/JSP authentication patterns", order: 210)]
class JavaMiscAuthTagger < FrameworkTagger
  include PrefixScope

  # Vert.x auth patterns
  VERTX_AUTH_PATTERNS = [
    {/AuthHandler/, "Vert.x AuthHandler"},
    # Vert.x 4's name for the same handlers (`SimpleAuthenticationHandler`).
    {/AuthenticationHandler/, "Vert.x AuthenticationHandler"},
    {/JWTAuth/, "Vert.x JWTAuth"},
    {/BasicAuthHandler/, "Vert.x BasicAuthHandler"},
    {/OAuth2AuthHandler/, "Vert.x OAuth2AuthHandler"},
    {/RedirectAuthHandler/, "Vert.x RedirectAuthHandler"},
    {/routingContext\.user\(\)/, "Vert.x user() check"},
  ]

  # Armeria auth patterns
  ARMERIA_AUTH_PATTERNS = [
    {/AuthService/, "Armeria AuthService decorator"},
    {/\.decorator\s*\(\s*AuthService/, "Armeria AuthService"},
    {/Authorizer/, "Armeria Authorizer"},
    {/BasicToken/, "Armeria BasicToken auth"},
    {/OAuth2Token/, "Armeria OAuth2Token auth"},
  ]

  # JSP/Servlet auth patterns
  JSP_AUTH_PATTERNS = [
    {/request\.getUserPrincipal\s*\(\)/, "Servlet getUserPrincipal"},
    {/request\.isUserInRole\s*\(/, "Servlet isUserInRole"},
    {/request\.getRemoteUser\s*\(\)/, "Servlet getRemoteUser"},
    {/HttpServletRequest.*getSession/, "Servlet session check"},
    {/<security-constraint>/, "web.xml security-constraint"},
    {/<auth-constraint>/, "web.xml auth-constraint"},
  ]

  ALL_PATTERNS = VERTX_AUTH_PATTERNS + ARMERIA_AUTH_PATTERNS + JSP_AUTH_PATTERNS

  VERTX_VERB = "(?:route|get|post|put|delete|patch|head|options|trace|connect)"

  # A Vert.x route registration, `router.route("/private/*").handler(...)`;
  # group 1 is its path (absent for `router.route()`, which covers every
  # route).
  VERTX_ROUTE = /\b\w+\s*\.\s*#{VERTX_VERB}\s*\(\s*(?:"([^"]*)"\s*)?\)\s*(?:\.\s*(?:handler|blockingHandler|respond|failureHandler|produces|consumes|order|subRouter)\b|$)/
  # The same registration chained on a receiver written on the line above.
  VERTX_CHAINED_ROUTE = /\A\s*\.\s*#{VERTX_VERB}\s*\(\s*(?:"([^"]*)"\s*)?\)/
  # `Route api = router.route("/api/*");`, whose `api.handler(..)` lines
  # register on that path.
  VERTX_ROUTE_ASSIGN = /\b([a-z_$][\w$]*)\s*=\s*[\w$.]+\s*\.\s*#{VERTX_VERB}\s*\(\s*(?:"([^"]*)"\s*)?\)\s*;?\s*\z/
  VERTX_ROUTE_USE    = /\A\s*([a-z_$][\w$]*)\s*\.\s*(?:handler|blockingHandler)\s*\(/
  HANDLER_VARIABLE   = /\.\s*(?:handler|blockingHandler)\s*\(\s*([a-z_$][\w$]*)\s*\)/
  HANDLER_METHOD_REF = /\.\s*(?:handler|blockingHandler)\s*\(\s*(?:this|[A-Z][\w$]*)?\s*::\s*([a-z_$][\w$]*)\s*\)/
  # A declared name: Java `Type name` before `=`, `;`, `,` or `)` (local,
  # field, parameter), Kotlin `val`/`var name` and `name: Type` parameters.
  DECLARATION = /(?:\b[A-Z][\w$.]*(?:<[^;=()]*>)?(?:\[\])?\s+|\b(?:val|var)\s+)([a-z_$][\w$]*)\s*(?=[=;,):]|\z)|[(,]\s*([a-z_$][\w$]*)\s*:\s*[A-Z]/
  # A method taking the RoutingContext: the target of `.handler(this::name)`.
  HANDLER_METHOD      = /\b([a-z_$][\w$]*)\s*\(\s*(?:final\s+)?(?:RoutingContext\s+[a-z_$][\w$]*|[a-z_$][\w$]*\s*:\s*RoutingContext)\s*\)/
  MAX_STATEMENT_LINES = 40

  # One Vert.x source file, read once. `code` has comments blanked,
  # `masked` string contents too; `depth` is the bracket depth at the start
  # of each line, counted on `masked`. `registrations` holds every route
  # registration's line and path in file order, `declarations` the lines
  # declaring each name, `methods` the line of each RoutingContext method.
  record VertxSource,
    code : Array(String),
    masked : Array(String),
    depth : Array(Int32),
    registrations : Array({Int32, String?}),
    declarations : Hash(String, Array(Int32)),
    methods : Hash(String, Int32)

  # One registration in an Armeria `Server.builder()` chain. The analyzer
  # reads that chain's decorators itself (`ArmeriaChainGuards`); the lines
  # around a registration are other routes' and other servers' calls, so
  # this tagger leaves those routes alone.
  ARMERIA_BUILDER_ROUTE = /\.\s*(?:service|serviceUnder|serviceIf|route|withRoute)\s*\(/

  @vertx_sources = Hash(String, VertxSource).new

  def self.target_techs : Array(String)
    ["java_vertx", "java_armeria", "java_jsp"]
  end

  private def check_endpoint(endpoint : Endpoint)
    endpoint.details.code_paths.each do |path_info|
      lines = read_file_lines(path_info.path)
      next if lines.nil?
      line_num = path_info.line
      next if line_num.nil?
      # Skip stale/out-of-range line refs: a line beyond the content we
      # read would crash the lines[idx] walks below with IndexError.
      next if line_num < 1 || line_num > lines.size
      line_idx = line_num - 1

      next if endpoint.details.technology == "java_armeria" && lines[line_idx].matches?(ARMERIA_BUILDER_ROUTE)

      if endpoint.details.technology == "java_vertx"
        if found = check_vertx(path_info.path, line_idx, endpoint.url)
          description = "Protected by #{found[0]}"
          endpoint.add_tag(Tag.new("auth", description, "java_misc_auth", requires: JavaAccess.signed_in(found[1], description)))
          return
        end
      elsif description = check_route_auth(lines, line_idx) || check_handler_body(lines, line_idx)
        endpoint.add_tag(Tag.new("auth", "Protected by #{description}", "java_misc_auth"))
        return
      end
    end
  end

  # The lines just above the route.
  private def check_route_auth(lines : Array(String), line_idx : Int32) : String?
    ([line_idx - 10, 0].max..line_idx).each do |idx|
      current = lines[idx]
      next if import_line?(current)
      ALL_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end
    nil
  end

  private def check_handler_body(lines : Array(String), line_idx : Int32) : String?
    ((line_idx + 1)..[line_idx + 15, lines.size - 1].min).each do |idx|
      current = lines[idx].strip
      ALL_PATTERNS.each do |pattern, desc|
        return desc if current.matches?(pattern)
      end
    end
    nil
  end

  # Vert.x runs, before a route's own handlers, the handlers of every route
  # registered earlier whose path covers it: `router.route("/private/*")
  # .handler(AuthHandler)` guards the routes under `/private` registered
  # after it, and no other. So the guard is read from those registrations'
  # statements and from the route's own, never from lines merely nearby (an
  # auth provider built there, `JWTAuth.create(..)`, guards nothing).
  #
  # The tag names the first guard found. What the route requires comes from
  # every handler those statements pass, one by one (`JavaAccess.vertx_handler`):
  # all of a covering route's, and all of the route's own but the last
  # (which serves the request) unless that one holds a guard the tag reads.
  private def check_vertx(path : String, line_idx : Int32, url : String) : {String, Array(Access::Clause)}?
    source = vertx_source(path) || return
    return if line_idx >= source.code.size
    found = nil
    requires = [] of Access::Clause
    statements = source.registrations.select { |idx, route_path| idx < line_idx && vertx_route_covers?(route_path, url) }.map { |idx, _| {idx, line_idx} }
    statements << {line_idx, source.code.size}
    own_router = router_of(source.code[line_idx])
    statements.each do |from, stop|
      found ||= vertx_pattern(vertx_guard_text(source, from, stop))
      own = from == line_idx
      label = source.code[from].strip
      text = statement(source, from, stop)
      args = handler_args(text)
      # A Kotlin trailing-lambda handler (`.handler { .. }`) is read whole.
      lambda = text.matches?(HANDLER_LAMBDA)
      cnf = Access::CNF.new
      args.each_with_index do |arg, index|
        expression = handler_expression(source, arg, from)
        cnf.concat(JavaAccess.vertx_handler(expression, own && !lambda && index == args.size - 1) { |rest| !vertx_pattern(rest).nil? })
      end
      cnf << [Access::Atom.new(:unresolved, label)] if (args.empty? && vertx_pattern(text)) || (lambda && !own)
      # A route registered on another router variable may not run before
      # this one: a sub-router's routes see the parent's only where it is
      # mounted, which is not read here.
      router = router_of(label)
      cnf = [[Access::Atom.new(:unresolved, label)]] if !own && !cnf.empty? && own_router && router && router != own_router
      requires.concat(Access.clauses(cnf, label, path, from + 1))
    end
    found ? {found, requires} : nil
  end

  ROUTER_RECEIVER = /\A\s*([a-z_$][\w$]*)\s*\.\s*#{VERTX_VERB}\s*\(/
  HANDLER_CALL    = /\.\s*(?:handler|blockingHandler)\s*\(/
  HANDLER_LAMBDA  = /\.\s*(?:handler|blockingHandler)\s*\{/

  private def router_of(line : String) : String?
    line.match(ROUTER_RECEIVER).try(&.[1])
  end

  # The argument of each `.handler(..)` call of a statement, in order.
  private def handler_args(text : String) : Array(String)
    args = [] of String
    pos = 0
    while (call = text.match(HANDLER_CALL, pos)) && (close = Noir::JSLiteralScanner.find_matching_paren(text, call.end(0) - 1))
      args << text[call.end(0)...close]
      pos = close + 1
    end
    args
  end

  # A handler argument with a variable replaced by the value it is declared
  # with, and a method reference by the method.
  private def handler_expression(source : VertxSource, arg : String, at : Int32) : String
    text = arg.strip
    if text.matches?(/\A[a-z_$][\w$]*\z/)
      declared = declaration_in_scope(source, text, at) || return text
      initializer(statement(source, declared, source.code.size), text) || text
    elsif (ref = text.match(/\A(?:this|[A-Z][\w$]*)?\s*::\s*([a-z_$][\w$]*)\z/)) && (head = source.methods[ref[1]]?)
      statement(source, head, source.code.size)
    else
      text
    end
  end

  # The expression `name` is declared with in `text`, up to the `;` or
  # line end that closes it; nil for a declaration without one.
  private def initializer(text : String, name : String) : String?
    return unless found = text.match(/(?<![\w$.])#{Regex.escape(name)}\s*(?::\s*[\w$.<>?]+\s*)?=(?!=)/)
    depth = 0
    quote = nil.as(Char?)
    index = found.end(0)
    start = index
    while index < text.size
      char = text[index]
      if open_quote = quote
        index += 1 if char == '\\'
        quote = nil if char == open_quote
      elsif char == '"' || char == '\''
        quote = char
      elsif char.in?('(', '[', '{')
        depth += 1
      elsif char.in?(')', ']', '}')
        break if (depth -= 1) < 0
      elsif depth == 0 && (char == ';' || (char == '\n' && !text[(index + 1)..].lstrip.starts_with?('.')))
        break
      end
      index += 1
    end
    text[start...index].strip
  end

  private def vertx_pattern(text : String) : String?
    ALL_PATTERNS.each do |pattern, desc|
      return desc if text.matches?(pattern)
    end
    nil
  end

  # The statement at `from` (ending before `stop`), with the declarations of
  # the handler variables and the bodies of the handler methods it passes.
  private def vertx_guard_text(source : VertxSource, from : Int32, stop : Int32) : String
    text = statement(source, from, stop)
    text.scan(HANDLER_VARIABLE) do |found|
      if declared = declaration_in_scope(source, found[1], from)
        text += "\n#{source.code[declared]}"
      end
    end
    text.scan(HANDLER_METHOD_REF) do |found|
      if head = source.methods[found[1]]?
        text += "\n#{statement(source, head, source.code.size)}"
      end
    end
    text
  end

  # The statement starting on line `from`: the lines still inside a bracket
  # it opens, or continuing its chain with a leading `.`, up to `stop` and
  # at most MAX_STATEMENT_LINES.
  private def statement(source : VertxSource, from : Int32, stop : Int32) : String
    level = source.depth[from]
    last = from
    limit = Math.min(stop, from + MAX_STATEMENT_LINES)
    while last + 1 < limit && (source.depth[last + 1] > level || source.masked[last + 1].lstrip.starts_with?('.'))
      last += 1
    end
    source.code[from..last].join('\n')
  end

  # The nearest declaration of `name` at or above line `at` whose block is
  # still open there: a parameter or local of the enclosing method, else a
  # field or constructor property. Another method's local is out of scope.
  # ponytail: a field declared below its use is not found.
  private def declaration_in_scope(source : VertxSource, name : String, at : Int32) : Int32?
    lines = source.declarations[name]? || return
    lines.reverse_each do |declared|
      next if declared > at
      level = source.depth[declared]
      return declared if ((declared + 1)..at).all? { |idx| source.depth[idx] >= level }
    end
    nil
  end

  private def vertx_source(path : String) : VertxSource?
    if cached = @vertx_sources[path]?
      return cached
    end
    content = read_file(path) || return
    code = Noir::KotlinSourceMask.code_only(content).split('\n')
    masked = Noir::KotlinSourceMask.visible(content).split('\n')
    depth = [] of Int32
    level = 0
    masked.each do |line|
      depth << level
      level += line.count("([{") - line.count(")]}")
    end
    registrations = [] of {Int32, String?}
    route_variables = Hash(String, String?).new
    declarations = Hash(String, Array(Int32)).new
    methods = Hash(String, Int32).new
    code.each_with_index do |line, idx|
      next if import_line?(line)
      if assigned = line.match(VERTX_ROUTE_ASSIGN)
        route_variables[assigned[1]] = assigned[2]?
      elsif route = line.match(VERTX_ROUTE) || line.match(VERTX_CHAINED_ROUTE)
        registrations << {idx, route[1]?}
      elsif (use = line.match(VERTX_ROUTE_USE)) && route_variables.has_key?(use[1])
        registrations << {idx, route_variables[use[1]]}
      end
      masked[idx].scan(DECLARATION) { |found| (declarations[found[1]? || found[2]] ||= [] of Int32) << idx }
      if head = masked[idx].match(HANDLER_METHOD)
        methods[head[1]] ||= idx
      end
    end
    @vertx_sources[path] = VertxSource.new(code, masked, depth, registrations, declarations, methods)
  end

  private def import_line?(line : String) : Bool
    line.lstrip.starts_with?("import ")
  end

  # Vert.x matches a path ending in `*` as a prefix and any other path
  # exactly.
  private def vertx_route_covers?(path : String?, url : String) : Bool
    return true if path.nil?
    return prefix_covers?(path.rchop('*'), url) if path.ends_with?('*')
    path.rstrip('/') == url.rstrip('/')
  end
end
