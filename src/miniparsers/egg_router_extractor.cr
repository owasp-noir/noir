require "./js_route_extractor"
require "../utils/top_level_split"
require "../utils/url_path"

module Noir
  # Egg.js router registrations, as written in `app/router.js` and the
  # `app/router/**` files it requires:
  #
  #   router.get('/users/:id', controller.user.show)
  #   router.post('login', '/login', auth, 'user.login')   // named route
  #   app.router.resources('posts', '/api/posts', controller.posts)
  #   const v1 = router.namespace('/v1'); v1.get('/ping', controller.ping.index)
  #
  # As in egg-core's router argument parsing, a second string argument
  # is the path only when three or more arguments are passed, and the last
  # argument is the controller.
  module EggRouterExtractor
    extend self

    # `verb` as written (`get`, `del`, `resources`, `redirect`, ...).
    # `handler` is the last argument's text: `controller.user.show`,
    # `'user.show'` or an inline function.
    record Route, verb : String, path : String, handler : String, line : Int32

    NAMESPACE = /(?<![\w$.])(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:app\.)?router\s*\.\s*namespace\s*\(\s*(['"`])([^'"`]+)\2/
    CALL      = /(?<![\w$.])((?:app\.)?[A-Za-z_$][\w$]*)\s*\.\s*(get|post|put|patch|delete|del|head|options|all|resources|redirect)\s*\(/

    def extract(content : String) : Array(Route)
      code = JSRouteExtractor.strip_js_comments(content)
      prefixes = {"router" => "", "app.router" => "", "app" => ""}
      code.scan(NAMESPACE) { |m| prefixes[m[1]] = m[3] }

      routes = [] of Route
      code.scan(CALL) do |m|
        prefix = prefixes[m[1]]? || next
        open = m.end(0) - 1
        close = JSRouteExtractor.find_matching_paren(code, open) || next
        args = TopLevelSplit.split(code[(open + 1)...close], ',', TopLevelSplit::Rules::JS_POSITIONAL_ARGS)
        args.pop if args.last? == "" # trailing comma
        next if args.size < 2

        # `redirect(source, destination, status)` is koa-router's own and
        # never takes a route name.
        named = m[2] != "redirect" && args.size >= 3 && string_literal(args[1])
        path = string_literal(named ? args[1] : args[0]) || next
        next unless path.starts_with?('/')

        routes << Route.new(m[2], URLPath.join(prefix, path), args.last, JSRouteExtractor.line_for_char_pos(code, m.begin(0)))
      end
      routes
    end

    # The value of a plain quoted string (no template interpolation).
    def string_literal(arg : String) : String?
      return if arg.size < 2
      quote = arg[0]
      return unless quote.in?('\'', '"', '`') && arg[-1] == quote
      value = arg[1...-1]
      value unless value.includes?(quote) || (quote == '`' && value.includes?("${"))
    end
  end
end
