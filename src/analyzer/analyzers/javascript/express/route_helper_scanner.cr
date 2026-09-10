require "../../../../models/code_locator"
require "../../../../utils/path_scope"
require "../../../../utils/top_level_split"
require "../../../../utils/url_path"
require "../../../../utils/text_file"
require "../../../../miniparsers/js_route_extractor"
require "../express_constants"
require "./js_module_resolver"

module Analyzer::Javascript
  # Express routes registered through a project-local *forwarding helper*
  # rather than by calling `router.get(...)` at the call site.
  #
  #   // src/routes/helpers.js
  #   helpers.setupApiRoute = function (...args) {
  #     const [router, verb, name] = args;
  #     ...
  #     router[verb](name, middlewares, tryRoute(controller));
  #   };
  #
  #   // src/routes/write/categories.js
  #   const { setupApiRoute } = require('../helpers');
  #   setupApiRoute(router, 'get', '/:cid', [], controllers.write.categories.get);
  #
  # The verb and the path are *arguments*, so no verb-DSL pattern matches
  # the call site, and the helper's own body carries no literal path — the
  # route is invisible to every other pass. NodeBB registers its entire
  # write API (208 calls), its page routes (69) and its admin page routes
  # (61) this way.
  #
  # ## What counts as a forwarding helper
  #
  # A function whose body calls `<recv>[<verb>](<path>, …)` or
  # `<recv>.<literal verb>(<path>, …)` where `<recv>` and `<path>` are both
  # bound to that function's own parameters. The binding may be direct
  # (`function (router, verb, name)`) or through a rest parameter that is
  # destructured positionally (`function (...args)` +
  # `const [router, verb, name] = args`), which is the shape NodeBB uses.
  #
  # ## Why this does not mint routes for arbitrary calls
  #
  # An earlier audit found ~250 NodeBB "endpoints" that were really HTTP
  # *client* calls in `test/*.js`. Anything that lets a plain function call
  # produce a route risks reopening that, so acceptance is deliberately
  # narrow:
  #
  #   * The receiver, the path — and, for the computed form, the verb —
  #     must all be parameters of the same function. `request.get(url)`
  #     inside `function fetch(url)` fails on the receiver.
  #   * The forwarded call must pass at least one argument after the path.
  #     A one-argument `client.get(url)` is not a registration.
  #   * The receiver parameter must be named like a router (`router`,
  #     `app`, `server`, `*Router`, `*App`, `*Server`). That is what
  #     separates a route helper from a generic client wrapper such as
  #     `function request(client, method, url) { client[method](url, o) }`,
  #     which satisfies every other condition.
  #   * At the call site both the verb and the path must be literals. A
  #     computed path yields nothing rather than a guess.
  #   * Definitions and call sites in test-stub / minified files are
  #     skipped, exactly as `JSRouteExtractor.extract_routes` skips them.
  class RouteHelperScanner
    include ExpressConstants

    HTTP_VERBS = %w[get post put delete patch head options all]

    # A forwarded registration inside a helper body. The receiver, the verb
    # and the path are all resolved to parameter positions of the helper.
    #
    #   router[verb](name, …)         → verb_arg: 1, path_arg: 2
    #   router.get(name, …)           → verb: "get", path_arg: 1
    #   router.get(`/api${name}`, …)  → verb: "get", path_arg: 1,
    #                                   path_before: "/api"
    record Forward,
      receiver : String,
      verb : String?,
      verb_arg : Int32?,
      path_arg : Int32,
      path_before : String,
      path_after : String,
      line : Int32

    # A helper definition: which argument carries the router, and what the
    # body forwards.
    record HelperSpec,
      name : String,
      router_arg : Int32,
      forwards : Array(Forward)

    # One route recovered from a call site. `args` and `path_arg` let the
    # analyzer walk the handler arguments for callees.
    record HelperRoute,
      method : String,
      url : String,
      line : Int32,
      args : Array(Tuple(String, Int32)),
      path_arg : Int32

    # The forwarded-registration shape, used both as the per-file gate and
    # as the extractor. Group 1 is the receiver, group 2 the verb variable
    # of the computed form, group 3 a literal verb, group 4 the path
    # expression. The trailing comma is what enforces "at least one
    # argument after the path".
    FORWARD_CALL_RE = /([A-Za-z_$][\w$]*)\s*(?:\[\s*([A-Za-z_$][\w$]*)\s*\]|\.\s*(get|post|put|delete|patch|head|options|all))\s*\(\s*(`[^`\n]*`|[A-Za-z_$][\w$]*)\s*,/

    # Function definitions whose parameter list can be read positionally.
    # The captured name is the local one; for `helpers.setupApiRoute = …`
    # it is the last dotted segment, which is also the name importers see
    # through `const { setupApiRoute } = require('./helpers')`.
    #
    # Every pattern ends at the opening parenthesis of the parameter list,
    # so `end(0) - 1` is that parenthesis.
    FUNCTION_DEF_RES = [
      /\bfunction\s+([A-Za-z_$][\w$]*)\s*\(/,
      /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?function\s*\*?\s*\(/,
      /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?\(/,
      /(?:^|[;{}\n])\s*(?:[A-Za-z_$][\w$]*\s*\.\s*)+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?function\s*\*?\s*\(/,
      /(?:^|[;{}\n])\s*(?:[A-Za-z_$][\w$]*\s*\.\s*)+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s+)?\(/,
    ]

    # Between the parameter list and the body there may only be syntactic
    # glue: `=>`, a TypeScript return type, whitespace. Anything else means
    # the `{` we found opens a later construct, not this function's body.
    FUNCTION_GLUE_RE  = /\A[\s=>:|,.<>\[\]A-Za-z_$0-9]*\z/
    FUNCTION_GLUE_MAX = 120

    # Ceiling on `functions x forward matches` in one file, past which the
    # innermost-enclosing-function attribution is abandoned rather than run.
    MAX_ATTRIBUTION_WORK = 1_000_000

    # `const [router, verb, name] = args` — the positional read of a rest
    # parameter. Holes (`const [, verb] = args`) keep their position.
    REST_DESTRUCTURE_RE = /(?:const|let|var)\s*\[([^\]\n]*)\]\s*=\s*([A-Za-z_$][\w$]*)/

    # A router-shaped parameter name. Required of the receiver, whichever
    # form the forward takes.
    #
    # This is the load-bearing false-positive guard. Without it a generic
    # client wrapper — `exports.request = function (client, method, url) {
    # return client[method](url, opts) }`, called as
    # `request(axios, 'get', '/api/remote/users')` — satisfies every other
    # condition, and every such call becomes a route. The computed
    # `recv[verb](path, …)` shape looked distinctive enough to exempt until
    # a hostile fixture showed it is exactly how a verb-parameterised HTTP
    # client is called.
    #
    # `api` is deliberately absent: `api[method](url, body)` on an axios
    # instance is a common client idiom. The cost of the rule is that a
    # helper whose router parameter is named something else (`r`, `mux`) is
    # not recognised, which is the narrow-but-defensible side of the trade.
    ROUTER_PARAM_RE = /\A_?(?:router|app|server|[A-Za-z_$][\w$]*(?:Router|App|Server|router|app|server))\z/

    # A test tree, matched on the scan-base-relative path. Broader than
    # `JSRouteExtractor.test_stub_only?`, which only fires on dedicated
    # mock/e2e directories and so lets a plain `test/api.js` through —
    # NodeBB's does exactly that. A route helper invoked from a test is
    # never a production registration, and this pass only ever *adds*
    # endpoints, so excluding the whole test tree costs nothing real.
    TEST_TREE_RE = %r{(?:\A|/)(?:tests?|specs?|e2e|e2e-tests|__tests__|__mocks__|cypress|playwright)/|[.\-](?:test|spec)\.[jt]sx?\z}

    NAMED_IMPORT_RES = [
      /(?:const|let|var)\s*\{\s*([\s\S]*?)\s*\}\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/,
      /import\s*\{\s*([\s\S]*?)\s*\}\s*from\s*['"]([^'"]+)['"]/,
    ]

    MODULE_IMPORT_RES = [
      /(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*require\s*\(\s*['"]([^'"]+)['"]\s*\)/,
      /import\s+([A-Za-z_$][\w$]*)\s+from\s*['"]([^'"]+)['"]/,
    ]

    # Defining file → helper name → spec.
    getter helpers : Hash(String, Hash(String, HelperSpec))

    def initialize(
      @all_files : Array(String),
      @base_paths : Array(String),
      @base_path : String,
      @logger : NoirLogger,
    )
      @helpers = Hash(String, Hash(String, HelperSpec)).new
      @call_regex_cache = Hash(String, Regex).new
    end

    def any_helpers? : Bool
      !@helpers.empty?
    end

    # PASS 1: index every forwarding helper in the tree.
    def index : Nil
      @all_files.each do |file|
        next unless ExpressConstants::JS_EXTENSIONS.any? { |ext| file.ends_with?(ext) }
        next unless @base_paths.any? { |base| Noir::PathScope.under_root?(file, base) }

        content = begin
          CodeLocator.instance.content_for(file) || Noir::TextFile.read(file)
        rescue e : File::NotFoundError | File::Error | IO::Error
          @logger.debug "Error reading #{file} for route helpers (#{e.class}): #{e.message}"
          next
        end

        next unless content.matches?(FORWARD_CALL_RE, options: Noir::TextFile::MATCH_OPTIONS)
        next if Noir::JSRouteExtractor.minified_content?(content)
        next if test_tree?(file)
        next if Noir::JSRouteExtractor.test_stub_only?(file, content)

        found = index_file(file, Noir::JSRouteExtractor.strip_js_comments(content))
        # Keyed absolute, because `JsModuleResolver` hands back absolute
        # paths and `@all_files` is relative whenever the scan base is.
        @helpers[File.expand_path(file)] = found unless found.empty?
      end
    end

    # Lines of the forwarded calls inside the helpers defined in `file`.
    # `Express` uses them to drop the phantom endpoint the generic parser
    # mints from a helper's own `router.get(`/api${name}`, …)`: that line
    # declares a rewrite, it does not register a path.
    def forward_lines(file : String) : Set(Int32)
      lines = Set(Int32).new
      if specs = @helpers[File.expand_path(file)]?
        specs.each_value { |spec| spec.forwards.each { |forward| lines << forward.line } }
      end
      lines
    end

    # PASS 2: routes registered by calling an indexed helper from `file`.
    def routes_for(file : String, content : String) : Array(HelperRoute)
      routes = [] of HelperRoute
      return routes if @helpers.empty?
      # Same two exclusions `JSRouteExtractor.extract_routes` applies to
      # its own call sites. A test file that drives the API through the
      # project's own helper would otherwise mint the routes a second
      # time — and NodeBB's `test/` tree was already the source of a
      # ~250-endpoint false-positive class once.
      return routes if Noir::JSRouteExtractor.minified_content?(content)
      return routes if test_tree?(file)
      return routes if Noir::JSRouteExtractor.test_stub_only?(file, content)

      callables = callable_helpers(file, content)
      return routes if callables.empty?

      # Blank out comments before looking for call sites. NodeBB parks a
      # commented-out `// setupApiRoute(router, 'post', '/', …)` in
      # src/routes/write/search.js, and without this it becomes an endpoint.
      # `strip_js_comments` replaces comment characters in place, so every
      # offset and line number below still refers to the real file.
      content = Noir::JSRouteExtractor.strip_js_comments(content)

      prefixes = file_prefixes(file)
      lines = LineIndex.new(content)
      seen = Set(Tuple(String, String)).new

      callables.each do |call_expr, spec|
        content.scan(call_regex(call_expr)) do |m|
          match_end = m.end(0)
          next unless match_end
          open_paren = match_end - 1
          close_paren = Noir::JSRouteExtractor.find_matching_paren(content, open_paren)
          next unless close_paren

          args = Noir::TopLevelSplit.split_spans(content, ',',
            Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS, open_paren + 1, close_paren)
          next if args.size <= spec.router_arg

          line = lines.line_at(m.begin(0) || open_paren)

          spec.forwards.each do |forward|
            method = call_site_verb(forward, args)
            next unless method
            raw_path = call_site_path(forward, args)
            next unless raw_path

            path = forward.path_before + raw_path + forward.path_after
            prefixes.each do |prefix|
              url = prefix.empty? ? path : Noir::URLPath.join(prefix, path)
              next unless seen.add?({method, url})
              routes << HelperRoute.new(method, url, line, args, forward.path_arg)
            end
          end
        end
      end

      routes
    end

    # ------------------------------------------------------------------
    # Helper indexing
    # ------------------------------------------------------------------

    private record ForwardMatch,
      pos : Int32,
      receiver : String,
      verb_var : String?,
      literal_verb : String?,
      path_expr : String

    private record FunctionDef,
      name : String,
      params_open : Int32,
      params_close : Int32,
      body_start : Int32,
      body_end : Int32

    private def index_file(file : String, content : String) : Hash(String, HelperSpec)
      specs = Hash(String, HelperSpec).new

      matches = forward_matches(content)
      return specs if matches.empty?

      functions = function_defs(content)
      return specs if functions.empty?
      # Attribution below is O(functions x matches). Both are small in real
      # source (NodeBB's helpers.js: 5 x 5), but a generated file could push
      # the product high enough to matter, and no route is worth an
      # unbounded walk. Give up on the file instead.
      if functions.size.to_i64 * matches.size > MAX_ATTRIBUTION_WORK
        @logger.debug "Skipping #{file} for route helpers (#{functions.size} functions x #{matches.size} forwards)"
        return specs
      end

      lines = LineIndex.new(content)

      # Attribute each forwarded call to the innermost function containing
      # it, so a callback nested in a helper does not turn its enclosing
      # helper into a second, wider definition.
      by_function = Hash(Int32, Array(ForwardMatch)).new { |h, k| h[k] = [] of ForwardMatch }
      matches.each do |match|
        best = nil.as(Int32?)
        best_span = Int32::MAX
        functions.each_with_index do |func, idx|
          next unless func.body_start < match.pos && match.pos < func.body_end
          span = func.body_end - func.body_start
          if span < best_span
            best_span = span
            best = idx
          end
        end
        by_function[best] << match if best
      end

      by_function.each do |func_idx, func_matches|
        func = functions[func_idx]
        param_index = parameter_positions(content, func)
        next if param_index.empty?

        forwards = [] of Forward
        func_matches.each do |match|
          forward = build_forward(match, param_index, lines)
          next unless forward
          next if forwards.any? { |f| same_forward?(f, forward) }
          forwards << forward
        end
        next if forwards.empty?
        # At least one forward must pass the path parameter *bare*. A
        # function whose every registration wraps the parameter in literal
        # text — `_mounts.post = (app, name, …) => app.get(`/${name}/:pid`,
        # …)` — is not forwarding a caller's path, it is registering a
        # fixed route that happens to interpolate a constant. The generic
        # parser already emits those correctly (`/{name}/:pid`), and
        # indexing them here would both duplicate and suppress them.
        next unless forwards.any? { |forward| forward.path_before.empty? && forward.path_after.empty? }

        router_arg = param_index[forwards.first.receiver]?
        next unless router_arg

        specs[func.name] = HelperSpec.new(func.name, router_arg, forwards)
        @logger.debug "Indexed Express route helper #{file}:#{func.name} (#{forwards.size} forward(s))"
      end

      specs
    end

    private def same_forward?(a : Forward, b : Forward) : Bool
      a.verb == b.verb && a.verb_arg == b.verb_arg && a.path_arg == b.path_arg &&
        a.path_before == b.path_before && a.path_after == b.path_after
    end

    private def forward_matches(content : String) : Array(ForwardMatch)
      matches = [] of ForwardMatch
      content.scan(FORWARD_CALL_RE) do |m|
        pos = m.begin(0)
        next unless pos
        matches << ForwardMatch.new(pos, m[1], m[2]?, m[3]?, m[4])
      end
      matches
    end

    private def build_forward(match : ForwardMatch, param_index : Hash(String, Int32),
                              lines : LineIndex) : Forward?
      return unless param_index.has_key?(match.receiver)

      return unless match.receiver.matches?(ROUTER_PARAM_RE)

      verb : String? = nil
      verb_arg : Int32? = nil
      if verb_var = match.verb_var
        verb_arg = param_index[verb_var]?
        return unless verb_arg
      elsif literal_verb = match.literal_verb
        verb = literal_verb.downcase
      else
        return
      end

      path_arg, before, after = parse_path_expression(match.path_expr, param_index)
      return unless path_arg

      Forward.new(match.receiver, verb, verb_arg, path_arg, before, after, lines.line_at(match.pos))
    end

    # `name` → the parameter itself; `` `/api${name}` `` → the parameter
    # wrapped in literal text. A template carrying anything other than a
    # single `${param}` interpolation is refused: the rest of it would have
    # to be guessed at.
    private def parse_path_expression(expr : String, param_index : Hash(String, Int32)) : Tuple(Int32?, String, String)
      none = {nil.as(Int32?), "", ""}

      if expr.starts_with?('`')
        inner = expr[1...-1]
        m = inner.match(/\A([^$`]*)\$\{\s*([A-Za-z_$][\w$]*)\s*\}([^$`]*)\z/)
        return none unless m
        idx = param_index[m[2]]?
        return none unless idx
        return {idx, m[1], m[3]}
      end

      idx = param_index[expr]?
      return none unless idx
      {idx, "", ""}
    end

    private def function_defs(content : String) : Array(FunctionDef)
      defs = [] of FunctionDef
      seen = Set(Int32).new

      FUNCTION_DEF_RES.each do |pattern|
        content.scan(pattern) do |m|
          match_end = m.end(0)
          next unless match_end
          params_open = match_end - 1
          next unless seen.add?(params_open)

          params_close = Noir::JSRouteExtractor.find_matching_paren(content, params_open)
          next unless params_close

          body_start = content.index('{', params_close + 1)
          next unless body_start
          next if body_start - params_close > FUNCTION_GLUE_MAX
          next unless content[(params_close + 1)...body_start].matches?(FUNCTION_GLUE_RE)

          body_end = Noir::JSRouteExtractor.find_matching_brace(content, body_start)
          next unless body_end

          defs << FunctionDef.new(m[1], params_open, params_close, body_start, body_end)
        end
      end

      defs
    end

    # Parameter name → positional index. A rest parameter contributes the
    # positions its positional destructuring assigns inside the body.
    private def parameter_positions(content : String, func : FunctionDef) : Hash(String, Int32)
      positions = Hash(String, Int32).new
      params = Noir::TopLevelSplit.split_spans(content, ',',
        Noir::TopLevelSplit::Rules::JS_POSITIONAL_ARGS, func.params_open + 1, func.params_close)

      rest_name : String? = nil
      params.each_with_index do |entry, idx|
        text = entry[0].strip
        next if text.empty?
        if text.starts_with?("...")
          rest_name = text[3..].strip.split(/[\s:=]/).first?
          break
        end
        # Destructured or defaulted parameters have no positional name to
        # forward; they still occupy their position.
        next unless text =~ /\A([A-Za-z_$][\w$]*)\s*(?::|=|\z)/
        positions[$1] = idx
      end

      if rest = rest_name
        content[func.body_start..func.body_end].scan(REST_DESTRUCTURE_RE) do |m|
          next unless m[2] == rest
          m[1].split(',').each_with_index do |part, idx|
            name = part.strip
            next if name.empty? || name.starts_with?("...")
            next unless name =~ /\A([A-Za-z_$][\w$]*)\z/
            positions[name] = idx unless positions.has_key?(name)
          end
        end
      end

      positions
    end

    # ------------------------------------------------------------------
    # Call sites
    # ------------------------------------------------------------------

    # Helper call expressions reachable from `file`: helpers it defines
    # itself, helpers it destructures out of a relative import, and
    # `module.helper` property access on a whole-module import.
    private def callable_helpers(file : String, content : String) : Array(Tuple(String, HelperSpec))
      callables = [] of Tuple(String, HelperSpec)

      if own = @helpers[File.expand_path(file)]?
        own.each { |name, spec| callables << {name, spec} }
      end

      root = Noir::PathScope.longest_base(file, @base_paths) || @base_path

      NAMED_IMPORT_RES.each do |pattern|
        content.scan(pattern) do |m|
          specs = imported_helpers(file, m[2], root)
          next unless specs
          destructured_names(m[1]).each do |local, source|
            if spec = specs[source]?
              callables << {local, spec}
            end
          end
        end
      end

      # Whole-module imports, reachable two ways.
      module_specs = Hash(String, Hash(String, HelperSpec)).new
      MODULE_IMPORT_RES.each do |pattern|
        content.scan(pattern) do |m|
          specs = imported_helpers(file, m[2], root)
          next unless specs
          module_specs[m[1]] = specs
          #   const routeHelpers = require('../helpers')
          #   routeHelpers.setupApiRoute(…)
          specs.each { |name, spec| callables << {"#{m[1]}.#{name}", spec} }
        end
      end

      #   const routeHelpers = require('../helpers')
      #   const { setupApiRoute } = routeHelpers
      # NodeBB writes it this way in every one of its 15 write-API route
      # modules, so the one-step `= require(...)` form above is not enough.
      unless module_specs.empty?
        content.scan(/(?:const|let|var)\s*\{\s*([\s\S]*?)\s*\}\s*=\s*([A-Za-z_$][\w$]*)\s*[;\n]/) do |m|
          specs = module_specs[m[2]]?
          next unless specs
          destructured_names(m[1]).each do |local, source|
            if spec = specs[source]?
              callables << {local, spec}
            end
          end
        end
      end

      callables.uniq { |entry| entry[0] }
    end

    private def imported_helpers(file : String, specifier : String, root : String) : Hash(String, HelperSpec)?
      target = JsModuleResolver.resolve(file, specifier, root)
      return unless target
      @helpers[target]?
    end

    # `{ a, b: c, d as e }` → `{local, exported}` pairs:
    # `[{"a","a"}, {"c","b"}, {"e","d"}]`.
    private def destructured_names(body : String) : Array(Tuple(String, String))
      names = [] of Tuple(String, String)
      body.split(',').each do |raw|
        item = raw.strip
        next if item.empty?
        if item =~ /\A([A-Za-z_$][\w$]*)\s+as\s+([A-Za-z_$][\w$]*)\z/
          names << {$2, $1}
        elsif item =~ /\A([A-Za-z_$][\w$]*)\s*:\s*([A-Za-z_$][\w$]*)\z/
          names << {$2, $1}
        elsif item =~ /\A([A-Za-z_$][\w$]*)\z/
          names << {$1, $1}
        end
      end
      names
    end

    # `setupApiRoute(` but not `helpers.setupApiRoute(` — the dotted form
    # is indexed under its own call expression, and matching both would
    # emit every route twice.
    private def call_regex(call_expr : String) : Regex
      @call_regex_cache.fetch(call_expr) do
        escaped = call_expr.split('.').map { |part| Regex.escape(part) }.join("\\s*\\.\\s*")
        @call_regex_cache[call_expr] = Regex.new("(?<![.\\w$])#{escaped}\\s*\\(")
      end
    end

    private def call_site_verb(forward : Forward, args : Array(Tuple(String, Int32))) : String?
      if verb = forward.verb
        return Noir::JSRouteExtractor.normalize_http_method(verb)
      end
      idx = forward.verb_arg
      return unless idx
      raw = args[idx]?.try(&.[0])
      return unless raw
      literal = string_literal(raw)
      return unless literal
      return unless HTTP_VERBS.includes?(literal.downcase)
      Noir::JSRouteExtractor.normalize_http_method(literal)
    end

    private def call_site_path(forward : Forward, args : Array(Tuple(String, Int32))) : String?
      raw = args[forward.path_arg]?.try(&.[0])
      return unless raw
      path = string_literal(raw)
      return unless path
      return unless path.starts_with?("/")
      path
    end

    # A quoted or backticked literal, with the quotes removed. Backticks
    # keep any `${…}` they carry: the optimizer normalises those into
    # `{name}` placeholders, exactly as it does for the generic parser.
    private def string_literal(raw : String) : String?
      text = raw.strip
      return unless text.size >= 2
      first = text[0]
      return unless first == '\'' || first == '"' || first == '`'
      return unless text[-1] == first
      body = text[1...-1]
      return if body.empty?
      return if (first == '\'' || first == '"') && body.includes?(first)
      body
    end

    private def test_tree?(file : String) : Bool
      CodeLocator.instance.base_relative(file).matches?(TEST_TREE_RE)
    end

    # File-level mount prefixes recorded by `RouterMountScanner`, or a
    # single empty prefix when the file is not mounted anywhere.
    private def file_prefixes(file : String) : Array(String)
      prefixes = CodeLocator.instance.all(ExpressConstants.file_key(File.expand_path(file)))
      prefixes.empty? ? [""] : prefixes
    end

    # Char offset → 1-based line, in O(log n) per lookup after one linear
    # build. The alternative — `content[0...pos].count('\n')` per call —
    # is quadratic over a file with a couple of hundred helper calls, and
    # NodeBB has files with sixty of them.
    private class LineIndex
      def initialize(content : String)
        @newlines = [] of Int32
        content.each_char_with_index do |char, idx|
          @newlines << idx if char == '\n'
        end
      end

      def line_at(pos : Int32) : Int32
        low = 0
        high = @newlines.size
        while low < high
          mid = (low + high) // 2
          if @newlines[mid] < pos
            low = mid + 1
          else
            high = mid
          end
        end
        low + 1
      end
    end
  end
end
