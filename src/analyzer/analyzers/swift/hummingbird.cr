require "../../engines/swift_engine"
require "../../../miniparsers/swift_callee_extractor"

module Analyzer::Swift
  class Hummingbird < SwiftEngine
    # Maximum number of lines to look ahead for function parameters
    LOOKAHEAD_LIMIT = 20

    # Route-registration methods exposed by Hummingbird's `RouterMethods`
    # protocol. They all return `Self`, which is what makes the fluent
    # builder chain (`group.get(...).post(...)`) possible.
    HTTP_METHODS = %w[get post put patch delete head]

    ROUTE_BODY_LOOKAHEAD_LIMIT = 5
    FUNCTION_SIGNATURE_PATTERN = /\bfunc\s+([A-Za-z_]\w*)\s*\(/

    # `let group = router.group("path")` / `var api = router.group("v1")`
    GROUP_ASSIGN_PATTERN = /\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\.group\s*\(/
    # `let router = Router()` — establishes a root router-like receiver.
    ROUTER_ASSIGN_PATTERN = /\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*Router\s*[(<]/
    # `let routes = RouteCollection(context: ...)` — a mountable route group.
    ROUTE_COLLECTION_ASSIGN_PATTERN = /\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*\.)?RouteCollection\s*[(<]/
    # `router.group("admin") { admin in ... }` — closure-scoped group.
    GROUP_CLOSURE_PATTERN = /([A-Za-z_]\w*)\.group\s*\(/
    # A function parameter typed as a router/router-group/router-methods.
    ROUTER_PARAM_PATTERN = /([A-Za-z_]\w*)\s*:\s*(?:some\s+|any\s+|inout\s+)*(?:Router|RouterGroup|RouterMethods)\b/
    # Type declarations whose body can host a RouteCollection handler.
    TYPE_DECL_PATTERN = /\b(?:struct|class|extension|actor|enum)\s+([A-Za-z_]\w*)/
    alias ScopedPrefixKey = Tuple(String, String)

    # A route hit discovered by the chain scanner.
    record RouteHit,
      method : String,
      path : String,
      line_index : Int32,
      handler : String?

    # Prefixes bound to RouteCollection-style handlers via their call
    # sites. Keyed by configured base path plus enclosing type/free-function
    # name so same-named controllers in monorepos do not share prefixes.
    @controller_prefix_by_type = {} of ScopedPrefixKey => String
    @controller_prefix_by_func = {} of ScopedPrefixKey => String

    # Project-wide pre-pass: resolve RouteCollection prefixes before the
    # per-file scan so controller bodies in one file can pick up the
    # prefix declared at a call site in another.
    def analyze
      build_controller_prefixes
      super
    end

    def analyze_file(path : String) : Array(Endpoint)
      endpoints = [] of Endpoint
      lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
      stripped_lines = strip_code_lines(lines)
      include_callee = callees_needed?
      handler_bodies = named_handler_bodies(lines)
      base = configured_base_for(path)

      hits = collect_route_hits(stripped_lines, lines, base)
      # `HummingbirdRouter`'s declarative result-builder DSL (`RouterBuilder`,
      # `RouteGroup`, capitalized `Get`/`Post`/... primitives) is invisible to
      # the receiver-based chain scanner, so discover it in a second pass.
      hits.concat(collect_dsl_route_hits(stripped_lines, lines))

      hits.each do |hit|
        begin
          details = Details.new(PathInfo.new(path, hit.line_index + 1))
          endpoint = Endpoint.new(hit.path, hit.method, details)
          extract_path_params(hit.path, endpoint)

          if handler = hit.handler
            extract_named_handler_params(handler, handler_bodies, endpoint)
            attach_named_handler_callees(handler, handler_bodies, path, endpoint) if include_callee
          else
            extract_function_params(lines, hit.line_index + 1, endpoint)
            attach_route_callees(lines, hit.line_index, path, endpoint, handler_bodies) if include_callee
          end

          endpoints << endpoint
        rescue e
          logger.debug "Error processing endpoint: #{e.message}"
        end
      end

      endpoints
    end

    # ------------------------------------------------------------------
    # Chain-aware route discovery
    # ------------------------------------------------------------------

    # Scan the (comment/string-stripped) source for route registrations.
    # Detection is receiver-aware: a `.get(...)`/`.post(...)` call only
    # counts when its receiver is router-like (a tracked router/group
    # variable, a router-typed function parameter, or a continuation of
    # an already-open router chain). This is what keeps `env.get(...)`,
    # `storage.get(key:)` and friends out of the endpoint list.
    private def collect_route_hits(stripped_lines : Array(String), original_lines : Array(String), base : String) : Array(RouteHit)
      hits = [] of RouteHit
      prefix_by_receiver = {} of String => String
      group_prefix_stack = [] of Tuple(String, Int32)
      param_stack = [] of Tuple(String, Int32)
      type_stack = [] of Tuple(String, Int32, String)
      brace_depth = 0
      active_prefix : String? = nil
      active_paren_depth = 0
      # A builder chain whose route step ended in a trailing closure
      # (`.post("x") { ... }`) is suspended across the closure body so the
      # next leading-dot step (`.post("y") { ... }`) re-attaches to it.
      suspended_prefix : String? = nil
      suspended_depth = 0

      stripped_lines.each_with_index do |line, index|
        original = original_lines[index]
        type_prefix = type_stack.last?.try(&.[2]) || ""

        # Register router-like receivers introduced on this line *before*
        # scanning, so same-line closures (`router.group("api") { api in
        # api.get(...) }`) can resolve the freshly-bound receiver.
        register_router_assignment(line, type_prefix, prefix_by_receiver)
        register_group_assignment(line, original, prefix_by_receiver)
        register_group_closure(line, original, prefix_by_receiver, group_prefix_stack, brace_depth)
        register_router_param(line, prefix_by_receiver, param_stack, type_stack, brace_depth, base)

        # Manage a chain suspended across a trailing closure body. Once the
        # body has closed (brace depth is back to the suspend level), the
        # next leading-dot step resumes it; any other statement clears it.
        if suspended_prefix
          if brace_depth < suspended_depth
            suspended_prefix = nil
          elsif brace_depth == suspended_depth && !line.strip.empty?
            if line.lstrip.starts_with?('.')
              active_prefix = suspended_prefix if active_prefix.nil?
            end
            suspended_prefix = nil
          end
        end

        cursor = 0

        # Continuation of a chain opened on a previous line.
        if active_prefix && (active_paren_depth > 0 || line.lstrip.starts_with?('.'))
          result = scan_chain_segment(line, original, index, active_prefix, active_paren_depth, 0, hits)
          if result[:closed]
            suspended_prefix, suspended_depth = result[:prefix], brace_depth
            active_prefix = nil
            active_paren_depth = 0
            cursor = result[:stop]
          else
            active_prefix = result[:prefix]
            active_paren_depth = result[:paren_depth]
            brace_depth = update_scopes(line, brace_depth, group_prefix_stack, param_stack, type_stack, prefix_by_receiver, base)
            next
          end
        else
          active_prefix = nil
          active_paren_depth = 0
        end

        # Start (and possibly restart, for one-liners) chains on this line.
        started = false
        loop do
          start = find_chain_start(line, cursor, prefix_by_receiver, type_prefix)
          break unless start

          started = true
          result = scan_chain_segment(line, original, index, start[:prefix], 0, start[:start_col], hits)
          if result[:closed]
            suspended_prefix, suspended_depth = result[:prefix], brace_depth
            cursor = result[:stop] + 1
            active_prefix = nil
            active_paren_depth = 0
            break if cursor >= line.size
          else
            active_prefix = result[:prefix]
            active_paren_depth = result[:paren_depth]
            break
          end
        end

        # A line that is just a bare router-like receiver (e.g. `group`
        # before a leading-dot builder chain), or that ends in a
        # `RouteCollection(...)` constructor, opens a chain so the following
        # `.get(...)`/`.post(...)` continuations attach to it.
        if !started && active_prefix.nil?
          if bare = bare_receiver(line, prefix_by_receiver)
            active_prefix = bare
            active_paren_depth = 0
          elsif trailing_route_collection?(line)
            active_prefix = type_prefix
            active_paren_depth = 0
          end
        end

        brace_depth = update_scopes(line, brace_depth, group_prefix_stack, param_stack, type_stack, prefix_by_receiver, base)
      end

      hits
    end

    # Locate the first router-like receiver that opens a chain at or after
    # `from`. Returns the column of the `.` that begins the method call so
    # the chain scanner can pick up from there.
    private def find_chain_start(line : String, from : Int32, prefix_by_receiver : Hash(String, String), type_prefix : String)
      offset = from
      while offset < line.size
        slice = line[offset..]
        # `add` (i.e. `.add(middleware:)`) is a `Self`-returning builder step.
        # A chain that *opens* with it — `group.add(middleware: auth).get(use:)
        # .post("logout", use:)` — must be recognized so the trailing verb
        # steps attach; otherwise those routes silently vanish. (`.add` mid-chain
        # already works once some other step has opened the chain.)
        match = slice.match(/(?<![.\w])([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)\.(get|post|put|patch|delete|head|on|ws|group|add)\s*\(/)
        break unless match

        receiver = match[1]
        receiver_begin = offset + (match.begin(1) || 0)
        if router_like?(receiver, prefix_by_receiver)
          dot_col = receiver_begin + receiver.size
          return {prefix: prefix_for_receiver(receiver, prefix_by_receiver), start_col: dot_col}
        end

        offset = receiver_begin + receiver.size
      end

      # A `RouteCollection(context:).get(...)...` builder mounted into the
      # router elsewhere (via `addRoutes(_:atPath:)`). The constructor ends
      # in `)`, so the receiver-name scan above can't see it; pick it up by
      # walking to the close paren and checking for a trailing `.method(`.
      offset = from
      while marker = line.index("RouteCollection", offset)
        open = line.index('(', marker)
        if open && (args = call_arguments(line, open + 1))
          after = args[1] + 1
          if line[after..]?.try(&.lstrip).try(&.starts_with?('.'))
            dot_col = after + (line[after..].size - line[after..].lstrip.size)
            return {prefix: type_prefix, start_col: dot_col}
          end
        end
        offset = marker + "RouteCollection".size
      end

      nil
    end

    # A line consisting solely of a router-like receiver token (the head
    # of a multi-line builder chain). Returns its prefix, or nil.
    private def bare_receiver(line : String, prefix_by_receiver : Hash(String, String)) : String?
      trimmed = line.strip
      return if trimmed.empty?
      return unless trimmed.match(/^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*$/)
      return unless router_like?(trimmed, prefix_by_receiver)

      prefix_for_receiver(trimmed, prefix_by_receiver)
    end

    # True when a line ends with a `RouteCollection(...)` constructor (the
    # head of a `return RouteCollection(context:)` builder whose `.get`/
    # `.post` steps continue on the following leading-dot lines).
    private def trailing_route_collection?(line : String) : Bool
      marker = line.rindex("RouteCollection")
      return false unless marker

      open = line.index('(', marker)
      return false unless open

      args = call_arguments(line, open + 1)
      return false unless args

      (line[(args[1] + 1)..]? || "").strip.empty?
    end

    # Walk a single physical line of a router chain starting at `start_col`.
    # Updates the running prefix on `.group(...)` segments and records a
    # `RouteHit` for each HTTP-verb / `.on(...)` call. Returns the prefix,
    # the carried paren depth and whether a trailing closure (`{`) closed
    # the chain head on this line.
    private def scan_chain_segment(line : String,
                                   original : String,
                                   index : Int32,
                                   prefix : String,
                                   paren_depth : Int32,
                                   start_col : Int32,
                                   hits : Array(RouteHit))
      i = start_col
      closed = false
      stop = line.size

      while i < line.size
        char = line[i]

        if paren_depth > 0
          case char
          when '(', '['
            paren_depth += 1
          when ')', ']'
            paren_depth -= 1
          end
          i += 1
          next
        end

        case char
        when '{'
          closed = true
          stop = i
          break
        when '('
          paren_depth += 1
          i += 1
        when '['
          paren_depth += 1
          i += 1
        when ')', ']'
          paren_depth -= 1 if paren_depth > 0
          i += 1
        when '.'
          method_match = line[i..].match(/^\.([A-Za-z_]\w*)\s*(\(|\{)/)
          unless method_match
            i += 1
            next
          end

          method = method_match[1]
          # `.get { ... }` / `.post { ... }` — a verb with a trailing
          # closure and no path argument registers a root-relative route.
          if method_match[2] == "{"
            if verb = route_verb(method)
              hits << RouteHit.new(verb, join_paths(prefix, "/"), index, nil)
            end
            i += (method_match.end(0) || 1) - 1
            next
          end

          open_paren = i + (method_match.end(0) || 0) - 1
          # Structure comes from the stripped line, but argument *content*
          # (the path literal) must be read from the original source.
          args = call_arguments(original, open_paren + 1)

          unless args
            # Arguments spill onto following lines; account for the open
            # paren and let the continuation handling pick them up.
            paren_depth += 1
            i = open_paren + 1
            next
          end

          args_str = args[0]
          prefix = handle_chain_method(method, args_str, prefix, index, hits)
          i = args[1] + 1
        else
          i += 1
        end
      end

      {prefix: prefix, paren_depth: paren_depth, closed: closed, stop: stop}
    end

    # Apply one method call from a chain: `.group` extends the prefix,
    # HTTP verbs and `.on` emit route hits, anything else is ignored.
    private def handle_chain_method(method : String,
                                    args_str : String,
                                    prefix : String,
                                    index : Int32,
                                    hits : Array(RouteHit)) : String
      case method
      when "group"
        join_paths(prefix, parse_route_path(args_str))
      when "on"
        path = join_paths(prefix, parse_route_path(args_str))
        handler = handler_from_args(args_str)
        on_methods(args_str).each do |http_method|
          hits << RouteHit.new(http_method, path, index, handler)
        end
        prefix
      else
        if verb = route_verb(method)
          path = join_paths(prefix, parse_route_path(args_str))
          hits << RouteHit.new(verb, path, index, handler_from_args(args_str))
        end
        prefix
      end
    end

    # Map a builder method name to its HTTP verb. `ws` registers a
    # WebSocket upgrade, which is served over an HTTP GET.
    private def route_verb(method : String) : String?
      return method.upcase if HTTP_METHODS.includes?(method)
      return "GET" if method == "ws"
      nil
    end

    # Extract HTTP method(s) from an `.on(...)` argument list.
    # Handles `method: .GET`, `method: .get`, `method: [.GET, .POST]`
    # and `method: HTTPRequest.Method.get`.
    private def on_methods(args_str : String) : Array(String)
      methods = [] of String
      if marker = args_str.index("method:")
        rest = args_str[(marker + 7)..]
        rest.scan(/\.([A-Za-z]+)/) do |m|
          token = m[1].upcase
          methods << token if HTTP_METHODS.includes?(token.downcase) || token == "OPTIONS" || token == "TRACE" || token == "CONNECT"
        end
      end
      methods
    end

    # The named handler referenced via `use:` (e.g. `use: self.create`
    # yields "create"). The closure API labels it `use:`, the result-builder
    # DSL labels it `handler:` (`Post("signup", handler: self.signup)`).
    # Closures return nil so the caller knows to read the inline body instead.
    private def handler_from_args(args_str : String) : String?
      if match = args_str.match(/\b(?:use|handler):\s*(?:self\.)?([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)/)
        return match[1].split('.').last
      end
      nil
    end

    private def router_like?(receiver : String, prefix_by_receiver : Hash(String, String)) : Bool
      receiver.split('.').any? { |part| prefix_by_receiver.has_key?(part) }
    end

    # ------------------------------------------------------------------
    # HummingbirdRouter result-builder DSL discovery
    # ------------------------------------------------------------------

    # The capitalized result-builder primitives exposed by the
    # `HummingbirdRouter` module. Unlike the receiver-based closure API
    # (`router.get("x") { ... }`), routes are declared structurally:
    #
    #     let router = RouterBuilder(context: Context.self) {
    #         Get("/health") { _, _ in .ok }   // GET /health
    #         UserController(...)               // splices its `body` here
    #         RouteGroup("api") {
    #             Post("login", handler: self.login) // POST /api/login
    #         }
    #     }
    #
    #     struct UserController: RouterController {
    #         var body: some RouterMiddleware<Context> {
    #             RouteGroup("user") {
    #                 Put(handler: self.create)          // PUT  /user
    #                 Post("signup", handler: self.signup) // POST /user/signup
    #             }
    #         }
    #     }
    #
    # A route primitive is only honored when it sits *directly* inside a
    # route-emitting scope — a `RouterBuilder { }` block, a `RouteGroup { }`
    # block, or a `var/func ... some RouterMiddleware { }` controller body —
    # never inside a handler closure. That gating keeps look-alike PascalCase
    # constructors (a `Post(title:)` model, a `Get`-named type) out of the
    # endpoint list.
    DSL_VERB_RE    = /(?<![.\w])(Get|Post|Put|Patch|Delete|Head)\s*\(/
    DSL_GROUP_RE   = /(?<![.\w])RouteGroup\s*\(/
    DSL_BUILDER_RE = /(?<![.\w])RouterBuilder\s*[(<]/
    # `var body: some RouterMiddleware<Context>` / `func routes() -> some
    # RouterMiddleware<Context>` — the controller body that hosts the DSL.
    DSL_BODY_RE = /\bsome\s+RouterMiddleware\b/

    # One nesting level of the DSL. `:builder`/`:group` scopes emit routes;
    # `:handler` (a route's trailing closure) and `:other` (struct/func/etc.
    # bodies) do not.
    record DslScope, kind : Symbol, prefix : String

    private record DslMarker,
      col : Int32,
      kind : Symbol,
      verb : String,
      paren_col : Int32,
      end_col : Int32

    private def collect_dsl_route_hits(stripped_lines : Array(String), original_lines : Array(String)) : Array(RouteHit)
      hits = [] of RouteHit
      return hits unless stripped_lines.any? do |l|
                           l.includes?("RouterBuilder") || l.includes?("RouterMiddleware") || l.includes?("RouteGroup")
                         end

      stack = [] of DslScope
      pending : DslScope? = nil

      stripped_lines.each_with_index do |line, index|
        original = original_lines[index]
        cursor = 0

        while cursor < line.size
          brace_open = line.index('{', cursor)
          brace_close = line.index('}', cursor)
          marker = next_dsl_marker(line, cursor)

          # Earliest of the three events on this line wins (a marker and a
          # brace never share a column, so ties cannot occur).
          candidates = [] of Tuple(Int32, Symbol)
          candidates << {brace_open, :open} if brace_open
          candidates << {brace_close, :close} if brace_close
          candidates << {marker.col, :marker} if marker
          break if candidates.empty?

          event_col, event = candidates.min_by(&.[0])

          case event
          when :open
            stack << (pending || default_dsl_scope(stack))
            pending = nil
            cursor = event_col + 1
          when :close
            stack.pop?
            pending = nil
            cursor = event_col + 1
          when :marker
            if m = marker
              pending, cursor = handle_dsl_marker(m, line, original, index, stack, hits)
            end
          end
        end
      end

      hits
    end

    # Process one DSL marker. Returns the scope the *next* `{` should adopt
    # (or nil) and the column to resume scanning from.
    private def handle_dsl_marker(m : DslMarker,
                                  line : String,
                                  original : String,
                                  index : Int32,
                                  stack : Array(DslScope),
                                  hits : Array(RouteHit)) : Tuple(DslScope?, Int32)
      case m.kind
      when :verb
        args = call_arguments(original, m.paren_col + 1)
        args_str = args ? args[0] : ""
        if dsl_emitting?(stack)
          path = join_paths(current_dsl_prefix(stack), parse_route_path(args_str))
          hits << RouteHit.new(m.verb.upcase, path, index, handler_from_args(args_str))
        end
        # A trailing closure on this verb is its handler body, not a group.
        {DslScope.new(:handler, current_dsl_prefix(stack)), args ? args[1] + 1 : m.end_col}
      when :group
        args = call_arguments(original, m.paren_col + 1)
        args_str = args ? args[0] : ""
        prefix = join_paths(current_dsl_prefix(stack), parse_route_path(args_str))
        {DslScope.new(:group, prefix), args ? args[1] + 1 : m.end_col}
      else
        # :builder / :body — a route-emitting root rooted at "".
        {DslScope.new(:builder, ""), m.end_col}
      end
    end

    # The earliest DSL marker at or after `cursor`, or nil.
    private def next_dsl_marker(line : String, cursor : Int32) : DslMarker?
      slice = line[cursor..]
      best : DslMarker? = nil

      if m = slice.match(DSL_VERB_RE)
        best = pick_marker(best, DslMarker.new(
          cursor + (m.begin(0) || 0), :verb, m[1],
          cursor + (m.end(0) || 0) - 1, cursor + (m.end(0) || 0)))
      end
      if m = slice.match(DSL_GROUP_RE)
        best = pick_marker(best, DslMarker.new(
          cursor + (m.begin(0) || 0), :group, "",
          cursor + (m.end(0) || 0) - 1, cursor + (m.end(0) || 0)))
      end
      if m = slice.match(DSL_BUILDER_RE)
        best = pick_marker(best, DslMarker.new(
          cursor + (m.begin(0) || 0), :builder, "",
          cursor + (m.end(0) || 0) - 1, cursor + (m.end(0) || 0)))
      end
      if m = slice.match(DSL_BODY_RE)
        best = pick_marker(best, DslMarker.new(
          cursor + (m.begin(0) || 0), :body, "", -1, cursor + (m.end(0) || 0)))
      end

      best
    end

    private def pick_marker(current : DslMarker?, candidate : DslMarker) : DslMarker
      return candidate unless current
      candidate.col < current.col ? candidate : current
    end

    # True when the innermost scope emits routes (a builder or group block,
    # not a handler closure or an unrelated `{ }`).
    private def dsl_emitting?(stack : Array(DslScope)) : Bool
      if top = stack.last?
        top.kind == :builder || top.kind == :group
      else
        false
      end
    end

    private def current_dsl_prefix(stack : Array(DslScope)) : String
      stack.reverse_each do |scope|
        return scope.prefix if scope.kind == :builder || scope.kind == :group
      end
      ""
    end

    # A `{` with no preceding marker. Inside a route-emitting scope it is a
    # transparent control-flow block (`if`/`for` in the result builder) and
    # stays emitting at the same prefix; otherwise it is an opaque body.
    private def default_dsl_scope(stack : Array(DslScope)) : DslScope
      if dsl_emitting?(stack)
        DslScope.new(:group, current_dsl_prefix(stack))
      else
        DslScope.new(:other, "")
      end
    end

    # ------------------------------------------------------------------
    # Receiver registration
    # ------------------------------------------------------------------

    private def register_router_assignment(line : String, type_prefix : String, prefix_by_receiver : Hash(String, String))
      # `let router = Router()` roots at "/"; `let routes = RouteCollection(...)`
      # inherits the prefix its enclosing controller is mounted at.
      if match = line.match(ROUTER_ASSIGN_PATTERN)
        prefix_by_receiver[match[1]] = ""
      elsif match = line.match(ROUTE_COLLECTION_ASSIGN_PATTERN)
        prefix_by_receiver[match[1]] = type_prefix
      end
    end

    private def register_group_assignment(line : String, original : String, prefix_by_receiver : Hash(String, String))
      match = line.match(GROUP_ASSIGN_PATTERN)
      return unless match

      variable = match[1]
      base = match[2]
      args = call_arguments(original, match.end(0) || 0)
      return unless args

      prefix_by_receiver[variable] = join_paths(prefix_for_receiver(base, prefix_by_receiver), parse_route_path(args[0]))
    end

    private def register_group_closure(line : String,
                                       original : String,
                                       prefix_by_receiver : Hash(String, String),
                                       group_prefix_stack : Array(Tuple(String, Int32)),
                                       brace_depth : Int32)
      match = line.match(GROUP_CLOSURE_PATTERN)
      return unless match

      base = match[1]
      return unless router_like?(base, prefix_by_receiver)

      args = call_arguments(original, match.end(0) || 0)
      return unless args

      after_call = line[(args[1] + 1)..]? || ""
      closure_match = after_call.match(/^\s*\{\s*([A-Za-z_]\w*)\s+in/)
      return unless closure_match

      variable = closure_match[1]
      prefix_by_receiver[variable] = join_paths(prefix_for_receiver(base, prefix_by_receiver), parse_route_path(args[0]))
      group_prefix_stack << {variable, brace_depth + 1}
    end

    # Register a router/router-group function parameter (e.g. the `group`
    # in `func addRoutes(to group: RouterGroup<Context>)`) as a router-like
    # receiver, lifting any prefix resolved for the enclosing type or
    # free function from the controller pre-pass.
    private def register_router_param(line : String,
                                      prefix_by_receiver : Hash(String, String),
                                      param_stack : Array(Tuple(String, Int32)),
                                      type_stack : Array(Tuple(String, Int32, String)),
                                      brace_depth : Int32,
                                      base : String)
      func_match = line.match(FUNCTION_SIGNATURE_PATTERN)
      return unless func_match

      param_match = line.match(ROUTER_PARAM_PATTERN)
      return unless param_match

      param = param_match[1]
      func_name = func_match[1]
      type_name = type_stack.last?.try(&.[0])

      prefix = ""
      if type_name && (bound = @controller_prefix_by_type[{base, type_name}]?)
        prefix = bound
      elsif bound = @controller_prefix_by_func[{base, func_name}]?
        prefix = bound
      end

      prefix_by_receiver[param] = prefix
      param_stack << {param, brace_depth + 1}
    end

    # Track brace depth and unwind scope-bound receivers (closure groups,
    # router params) and type declarations as their blocks close.
    private def update_scopes(line : String,
                              brace_depth : Int32,
                              group_prefix_stack : Array(Tuple(String, Int32)),
                              param_stack : Array(Tuple(String, Int32)),
                              type_stack : Array(Tuple(String, Int32, String)),
                              prefix_by_receiver : Hash(String, String),
                              base : String) : Int32
      if match = line.match(TYPE_DECL_PATTERN)
        if line.includes?('{')
          bound = @controller_prefix_by_type[{base, match[1]}]? || ""
          type_stack << {match[1], brace_depth + 1, bound}
        end
      end

      depth = brace_depth + line.count('{') - line.count('}')

      while !group_prefix_stack.empty? && depth < group_prefix_stack.last[1]
        variable, _ = group_prefix_stack.pop
        prefix_by_receiver.delete(variable)
      end

      while !param_stack.empty? && depth < param_stack.last[1]
        variable, _ = param_stack.pop
        prefix_by_receiver.delete(variable)
      end

      while !type_stack.empty? && depth < type_stack.last[1]
        type_stack.pop
      end

      depth
    end

    # ------------------------------------------------------------------
    # Controller (RouteCollection) prefix resolution — cross-file pre-pass
    # ------------------------------------------------------------------

    private def build_controller_prefixes
      files = swift_source_files
      return if files.empty?

      route_methods_by_base = Hash(String, Set(String)).new do |hash, key|
        hash[key] = Set{"addRoutes"} # `addRoutes` is the RouteCollection built-in
      end
      assignments = {} of ScopedPrefixKey => String # {base, variable} -> constructed type

      files.each do |path|
        base = configured_base_for(path)
        lines = strip_code_lines(File.read_lines(path, encoding: "utf-8", invalid: :skip))
        lines.each do |line|
          if (func = line.match(FUNCTION_SIGNATURE_PATTERN)) && line.match(ROUTER_PARAM_PATTERN)
            route_methods_by_base[base] << func[1]
          end
          if assign = line.match(/\b(?:let|var)\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*[(<]/)
            assignments[{base, assign[1]}] = assign[2]
          end
        end
      end

      files.each do |path|
        base = configured_base_for(path)
        register_controller_call_sites(path, route_methods_by_base[base], assignments, base)
      end
    end

    private def register_controller_call_sites(path : String,
                                               method_set : Set(String),
                                               assignments : Hash(ScopedPrefixKey, String),
                                               base : String)
      original_lines = File.read_lines(path, encoding: "utf-8", invalid: :skip)
      stripped_lines = strip_code_lines(original_lines)

      merge_logical_lines(stripped_lines, original_lines) do |stripped, original|
        method_set.each do |func_name|
          search_from = 0
          while marker = stripped.index(".#{func_name}", search_from)
            search_from = marker + func_name.size + 1
            # Require the call to be exactly `.<func>(` — guards against
            # partial matches like `.addRoutesLater(`.
            open = stripped.index('(', marker)
            next unless open && stripped[(marker + 1)...open].strip == func_name

            args = call_arguments(original, open + 1)
            next unless args

            args_str = args[0]
            before = original[0...marker]

            prefix = at_path_prefix(args_str) || labeled_group_prefix(args_str) || chain_group_prefix(before)

            controller = positional_controller_type(args_str, assignments, base) ||
                         resolve_type(receiver_before(before), assignments, base)

            if controller
              @controller_prefix_by_type[{base, controller}] ||= prefix
            end
            @controller_prefix_by_func[{base, func_name}] ||= prefix
          end
        end
      end
    end

    # Merge physical lines into logical statements: a line continues the
    # previous one while parentheses/brackets stay open or the next line
    # begins with a leading dot (fluent-chain continuation).
    private def merge_logical_lines(stripped_lines : Array(String), original_lines : Array(String), &)
      i = 0
      n = stripped_lines.size
      while i < n
        buf_s = [stripped_lines[i]]
        buf_o = [original_lines[i]]
        depth = paren_delta(stripped_lines[i])
        j = i
        while j + 1 < n && (depth > 0 || stripped_lines[j + 1].lstrip.starts_with?('.'))
          j += 1
          buf_s << stripped_lines[j]
          buf_o << original_lines[j]
          depth += paren_delta(stripped_lines[j])
        end
        yield buf_s.join("\n"), buf_o.join("\n")
        i = j + 1
      end
    end

    private def paren_delta(line : String) : Int32
      line.count('(') + line.count('[') - line.count(')') - line.count(']')
    end

    # `atPath: "/todos"` mount label -> "/todos".
    private def at_path_prefix(args : String) : String?
      if match = args.match(/\batPath:\s*["']([^"']*)["']/)
        return parse_route_path("\"#{match[1]}\"")
      end
      nil
    end

    # `to: router.group("api/todos")` -> "/api/todos"; `to: router` -> "".
    private def labeled_group_prefix(args : String) : String?
      if match = args.match(/\bto:\s*([A-Za-z_][\w.]*(?:\s*\([^)]*\))?(?:\.[A-Za-z_]\w*\s*\([^)]*\))*)/)
        return chain_group_prefix(match[1])
      end
      nil
    end

    # Join every `.group("x")` literal found in a receiver expression.
    private def chain_group_prefix(expr : String) : String
      prefix = ""
      expr.scan(/\bgroup\s*\(\s*["']([^"']*)["']/) do |m|
        prefix = join_paths(prefix, parse_route_path("\"#{m[1]}\""))
      end
      prefix
    end

    # The first positional argument's controller type, e.g.
    # `TodoController(...).endpoints` -> "TodoController",
    # `controller.routes` -> resolved type of `controller`.
    private def positional_controller_type(args : String, assignments : Hash(ScopedPrefixKey, String), base : String) : String?
      first = first_positional_arg(args)
      return unless first
      return if first.includes?(':') && !first.includes?('(')

      if match = first.match(/^([A-Za-z_]\w*)\s*(?:<[^>]*>)?\s*\(/)
        return match[1]
      end
      if match = first.match(/^([A-Za-z_]\w*)\s*\./)
        return assignments[{base, match[1]}]?
      end
      nil
    end

    # The text of the first positional argument (nil if the first argument
    # is labeled, e.g. `to:`/`atPath:`).
    private def first_positional_arg(args : String) : String?
      depth = 0
      slice = ""
      args.each_char do |char|
        case char
        when '(', '[', '<' then depth += 1
        when ')', ']', '>' then depth -= 1
        when ','
          break if depth == 0
        end
        slice += char
      end
      slice = slice.strip
      return if slice.empty?
      # A leading `label:` marks this as a non-positional argument.
      return if slice.match(/^[A-Za-z_]\w*\s*:/) && !slice.match(/^[A-Za-z_]\w*\s*\(/)
      slice
    end

    # The receiver expression to the left of a `.method(` call.
    private def receiver_before(before : String) : String
      if match = before.match(/([A-Za-z_]\w*)(?:<[^>]*>)?(?:\([^()]*\))?\s*$/)
        return match[1]
      end
      ""
    end

    private def resolve_type(receiver : String, assignments : Hash(ScopedPrefixKey, String), base : String) : String?
      return if receiver.empty?
      # `TodoController(...).addRoutes(...)` keeps the type verbatim; a bare
      # lowercase variable resolves through its constructor assignment.
      if receiver[0].uppercase?
        receiver
      else
        assignments[{base, receiver}]?
      end
    end

    private def swift_source_files : Array(String)
      all_files.select do |path|
        File.exists?(path) && !File.directory?(path) &&
          File.extname(path) == ".swift" &&
          !swift_test_path?(path) && !swift_vendor_path?(path)
      end
    rescue
      [] of String
    end

    # ------------------------------------------------------------------
    # Path / parameter helpers
    # ------------------------------------------------------------------

    # Parse route path from route arguments. The path is the first quoted
    # string; `{id}`-style segments are normalized to `:id`.
    def parse_route_path(route_args : String) : String
      if match = route_args.match(/["']([^"']+)["']/)
        path = match[1]
        path = path.gsub(/\{(\w+)\}/, ":\\1")
        path = "/" + path unless path.starts_with?("/")
        return path
      end

      "/"
    end

    # Extract path parameters from the route pattern (e.g., :id, :userID)
    def extract_path_params(route : String, endpoint : Endpoint)
      route.scan(/:(\w+)/) do |match|
        param_name = match[1]
        endpoint.push_param(Param.new(param_name, "", "path"))
      end
    end

    # Extract parameters from an inline closure body.
    def extract_function_params(lines : Array(String), start_index : Int32, endpoint : Endpoint)
      in_function = false
      brace_count = 0
      seen_opening_brace = false

      existing_path_params = Set(String).new
      endpoint.params.each do |p|
        existing_path_params.add(p.name) if p.param_type == "path"
      end

      (start_index...[start_index + LOOKAHEAD_LIMIT, lines.size].min).each do |i|
        line = lines[i]

        if line.includes?(" in ")
          in_function = true
        end

        brace_count += line.count('{')
        if brace_count > 0
          seen_opening_brace = true
        end
        brace_count -= line.count('}')

        extract_params_from_line(line, endpoint, existing_path_params)

        if in_function && seen_opening_brace && brace_count == 0 && i > start_index
          break
        end

        if i > start_index && route_definition?(line)
          break
        end
      end
    end

    # Check if a line contains a route definition
    private def route_definition?(line : String) : Bool
      (line.includes?(".get(") || line.includes?(".post(") ||
        line.includes?(".put(") || line.includes?(".delete(") ||
        line.includes?(".patch(") || line.includes?(".head(") ||
        line.includes?(".on("))
    end

    private def attach_route_callees(lines : Array(String),
                                     route_index : Int32,
                                     path : String,
                                     endpoint : Endpoint,
                                     handler_bodies : Hash(String, Tuple(String, Int32)))
      body, start_line = route_body(lines, route_index)
      return if body.empty?

      callees = Noir::SwiftCalleeExtractor.callees_for_body(body, path, start_line)
      Noir::SwiftCalleeExtractor.attach_to(endpoint, callees)
    end

    private def attach_named_handler_callees(handler_name : String,
                                             handler_bodies : Hash(String, Tuple(String, Int32)),
                                             path : String,
                                             endpoint : Endpoint)
      body = handler_bodies[handler_name]?
      return unless body

      callees = Noir::SwiftCalleeExtractor.callees_for_body(body[0], path, body[1])
      Noir::SwiftCalleeExtractor.attach_to(endpoint, callees)
    end

    private def route_body(lines : Array(String), route_index : Int32) : Tuple(String, Int32)
      opening_index = route_index
      opening_brace = structural_opening_brace(lines[opening_index])
      unless opening_brace
        ((route_index + 1)...[route_index + ROUTE_BODY_LOOKAHEAD_LIMIT, lines.size].min).each do |index|
          break if route_definition?(strip_code_line(lines[index]))

          if brace_index = structural_opening_brace(lines[index])
            opening_index = index
            opening_brace = brace_index
            break
          end
        end
      end
      return {"", route_index + 2} unless opening_brace

      body_after_opening_brace(lines, opening_index, opening_brace)
    end

    private def structural_opening_brace(line : String) : Int32?
      stripped, _, _ = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, 0, false)
      stripped.index('{')
    end

    private def call_arguments(line : String, args_start : Int32) : Tuple(String, Int32)?
      depth = 1
      in_string = false
      escaped = false
      quote = '"'
      index = args_start

      while index < line.size
        char = line[index]

        if in_string
          if escaped
            escaped = false
          elsif char == '\\'
            escaped = true
          elsif char == quote
            in_string = false
          end
        elsif char == '"' || char == '\''
          in_string = true
          quote = char
        elsif char == '('
          depth += 1
        elsif char == ')'
          depth -= 1
          if depth == 0
            return {line[args_start...index], index}
          end
        end

        index += 1
      end

      nil
    end

    private def prefix_for_receiver(receiver : String, prefix_by_receiver : Hash(String, String)) : String
      receiver.split('.').reverse_each do |part|
        if prefix = prefix_by_receiver[part]?
          return prefix
        end
      end

      ""
    end

    private def join_paths(prefix : String, path : String) : String
      return normalize_path(path) if prefix.empty? || prefix == "/"
      return normalize_path(prefix) if path.empty? || path == "/"

      "#{normalize_path(prefix).rstrip("/")}/#{path.lstrip("/")}"
    end

    private def normalize_path(path : String) : String
      normalized = path.empty? ? "/" : path
      normalized = "/#{normalized}" unless normalized.starts_with?("/")
      normalized.gsub(%r{/+}, "/")
    end

    private def strip_code_line(line : String) : String
      stripped, _, _ = Noir::SwiftCalleeExtractor.strip_non_code_with_state(line, 0, false)
      stripped
    end

    # Strip comments and string contents across the whole file so brace,
    # paren and method scanning never trips over `}` inside a string or a
    # multi-line comment.
    private def strip_code_lines(lines : Array(String)) : Array(String)
      block_comment_depth = 0
      in_multiline_string = false
      lines.map do |line|
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          line,
          block_comment_depth,
          in_multiline_string
        )
        stripped
      end
    end

    private def extract_named_handler_params(handler_name : String,
                                             handler_bodies : Hash(String, Tuple(String, Int32)),
                                             endpoint : Endpoint)
      body = handler_bodies[handler_name]?
      return unless body

      existing_path_params = Set(String).new
      endpoint.params.each do |p|
        existing_path_params.add(p.name) if p.param_type == "path"
      end

      body[0].each_line do |line|
        extract_params_from_line(line, endpoint, existing_path_params)
      end
    end

    private def extract_params_from_line(line : String, endpoint : Endpoint, existing_path_params : Set(String))
      # Extract query parameters from request.uri.queryParameters
      if line.includes?("request.uri.queryParameters.get(") ||
         line.includes?("request.uri.queryParameters[")
        match = line.match(/request\.uri\.queryParameters\.get\(["']([^"']+)["']\)/) ||
                line.match(/request\.uri\.queryParameters\[["']([^"']+)["']\]/)
        if match
          query_name = match[1]
          endpoint.push_param(Param.new(query_name, "", "query"))
        end
      end

      # Extract body parameters from request.decode
      if line.includes?("request.decode(") || line.includes?("await request.decode")
        endpoint.push_param(Param.new("body", "", "json"))
      end

      # Extract headers from request.headers
      if line.includes?("request.headers[")
        match = line.match(/request\.headers\[["']([^"']+)["']\]/)
        if match
          header_name = match[1]
          endpoint.push_param(Param.new(header_name, "", "header"))
        end
      end

      # Extract cookies from request.cookies
      if line.includes?("request.cookies[")
        match = line.match(/request\.cookies\[["']([^"']+)["']\]/)
        if match
          cookie_name = match[1]
          endpoint.push_param(Param.new(cookie_name, "", "cookie"))
        end
      end

      # Extract path parameters from context.parameters.require / .get
      if line.includes?("context.parameters.require(") ||
         line.includes?("context.parameters.get(")
        match = line.match(/context\.parameters\.(require|get)\(["']([^"']+)["']\)/)
        if match
          param_name = match[2]
          if !existing_path_params.includes?(param_name)
            endpoint.push_param(Param.new(param_name, "", "path"))
            existing_path_params.add(param_name)
          end
        end
      end
    end

    private def named_handler_bodies(lines : Array(String)) : Hash(String, Tuple(String, Int32))
      bodies = {} of String => Tuple(String, Int32)
      block_comment_depth = 0
      in_multiline_string = false

      lines.each_with_index do |line, index|
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          line,
          block_comment_depth,
          in_multiline_string
        )
        match = stripped.match(FUNCTION_SIGNATURE_PATTERN)
        next unless match

        handler_name = match[1]
        next if bodies.has_key?(handler_name)

        opening = stripped.index('{')
        if opening
          bodies[handler_name] = body_after_opening_brace(lines, index, opening)
          next
        end

        if location = next_opening_brace(lines, index + 1, block_comment_depth, in_multiline_string)
          opening_index, opening_brace = location
          bodies[handler_name] = body_after_opening_brace(lines, opening_index, opening_brace)
        end
      end

      bodies
    end

    private def next_opening_brace(lines : Array(String),
                                   start_index : Int32,
                                   block_comment_depth : Int32,
                                   in_multiline_string : Bool) : Tuple(Int32, Int32)?
      (start_index...[start_index + LOOKAHEAD_LIMIT, lines.size].min).each do |index|
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          lines[index],
          block_comment_depth,
          in_multiline_string
        )
        if opening = stripped.index('{')
          return {index, opening}
        end

        break if stripped.match(FUNCTION_SIGNATURE_PATTERN)
      end

      nil
    end

    private def body_after_opening_brace(lines : Array(String), opening_index : Int32, opening_brace : Int32) : Tuple(String, Int32)
      route_line = lines[opening_index]
      first_fragment = route_line[(opening_brace + 1)..]? || ""
      clean_fragment, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(first_fragment, 0, false)
      body_lines = [] of String
      brace_count = 1 + clean_fragment.count('{') - clean_fragment.count('}')

      if brace_count <= 0
        closing_brace = clean_fragment.rindex('}')
        first_fragment = first_fragment[0...closing_brace] if closing_brace
        return {first_fragment, opening_index + 1}
      end

      body_lines << first_fragment
      index = opening_index + 1

      while index < lines.size && brace_count > 0
        line = lines[index]
        stripped, block_comment_depth, in_multiline_string = Noir::SwiftCalleeExtractor.strip_non_code_with_state(
          line,
          block_comment_depth,
          in_multiline_string
        )
        next_brace_count = brace_count + stripped.count('{') - stripped.count('}')

        if next_brace_count <= 0
          if line.strip != "}"
            closing_brace = stripped.rindex('}')
            body_lines << (closing_brace ? line[0...closing_brace] : line)
          end
          break
        end

        body_lines << line
        brace_count = next_brace_count
        index += 1
      end

      {body_lines.join("\n"), opening_index + 1}
    end
  end
end
