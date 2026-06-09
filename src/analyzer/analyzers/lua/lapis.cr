require "../../../models/analyzer"
require "../../../miniparsers/lua_callee_extractor"

module Analyzer::Lua
  # Lapis is a Lua/MoonScript web framework on top of OpenResty. Routes
  # can be expressed in several styles:
  #
  #   * Method-specific calls — `app:get("/path", handler)`,
  #     `app:post`, `app:put`, `app:delete`, `app:patch`,
  #     `app:head`, `app:options`.
  #   * Generic `app:match(path, handler)` and the named
  #     `app:match("name", "/path", handler)` form, both of which
  #     dispatch on any HTTP method.
  #   * Application-table style: `["/path"] = "handler_name"` or
  #     `["/path"] = function(self) ... end`.
  #   * MoonScript class actions: `"/path": =>` and the named form
  #     `[name: "/path"]: =>`.
  #
  # Path parameters use `:name` and splats use `*name`, which already
  # match noir's URL convention so they are surfaced verbatim. Lapis
  # route patterns additionally carry Lua-pattern constraints
  # (`:id[%d]`, `:slug[%w]`) and optional groups (`(/page/:page)`),
  # neither of which belong in a concrete URL — both are normalised
  # away. Sub-apps mounted with `app:include(...)` carry an
  # `app.path = "/prefix"` that every route inherits, so the prefix is
  # detected per file and prepended to the routes bound on that app.
  class Lapis < Analyzer
    # Crystal recompiles an interpolated regex literal on every evaluation
    # (a full PCRE2 JIT compile); the route matchers interpolate the
    # discovered app-variable alternation, so memoize them per alternation.
    @method_call_regexes = Hash(String, Regex).new
    @match_call_regexes = Hash(String, Regex).new

    HTTP_METHODS     = %w[GET POST PUT DELETE PATCH HEAD OPTIONS]
    FALLBACK_METHODS = ["GET", "POST", "PUT", "DELETE", "PATCH"]
    APP_VAR_RE       = /(?:^|[^A-Za-z0-9_])(?:local\s+)?([A-Za-z_]\w*)\s*=\s*lapis\.Application(?:\b|:extend|\s*\()/
    APP_PATH_RE      = /(?:^|[^A-Za-z0-9_.])([A-Za-z_]\w*)\.path\s*=\s*(['"])([^'"]*)\2/
    MOON_PATH_RE     = /@path\s*:\s*(['"])([^'"]*)\1/

    def analyze
      include_callee = any_to_bool(@options["include_callee"]?) || any_to_bool(@options["ai_context"]?)

      all_files.each do |path|
        next if File.directory?(path)
        next unless path.ends_with?(".lua") || path.ends_with?(".moon")
        # Skip Busted / OpenResty spec files. Lapis's own
        # `spec/**/*_spec.moon` and `spec_openresty/`/`spec_cqueues/`
        # trees define ~143 phantom routes against inline test
        # apps. Production Lua never adopts the `_spec` filename
        # or the `spec*/` directory layout.
        next if lapis_test_path?(path)

        content = read_file_content(path)
        process_file(path, content, include_callee)
      end

      @result
    end

    # Busted convention: `<name>_spec.lua` / `<name>_spec.moon`,
    # plus `spec/` / `spec_<variant>/` (e.g. `spec_openresty/`,
    # `spec_cqueues/`) directories anywhere in the path *below*
    # the configured `base_paths` root. The filename suffix is
    # unambiguous anywhere in the tree; the directory match is
    # anchored against `base_paths` (so our own fixture tree under
    # `spec/functional_test/fixtures/lua/...` doesn't accidentally
    # match) but otherwise walks every relative segment — vendored
    # Lapis sources frequently live at `<project>/lapis/spec/...`
    # and would slip past a top-segment-only check.
    private def lapis_test_path?(path : String) : Bool
      base = File.basename(path)
      return true if base.ends_with?("_spec.lua") || base.ends_with?("_spec.moon")
      expanded_path = File.expand_path(path)

      base_paths.any? do |root|
        next false unless path_under_root?(expanded_path, root)

        expanded_root = File.expand_path(root)
        expanded_root = expanded_root.rstrip('/') unless expanded_root == File::SEPARATOR
        tail = expanded_path[expanded_root.size..]?.try(&.lchop(File::SEPARATOR)) || ""
        tail.split(File::SEPARATOR).any? { |seg| seg == "spec" || seg.starts_with?("spec_") }
      end
    end

    private def process_file(path : String, content : String, include_callee : Bool)
      cleaned = strip_lua_comments(content)
      handler_bodies = if include_callee
                         Noir::LuaCalleeExtractor.function_bodies(content, path)
                       else
                         {} of String => Noir::LuaCalleeExtractor::FunctionBody
                       end
      app_vars = detect_app_vars(cleaned)
      app_paths = detect_app_paths(cleaned, app_vars)
      moon_prefix = detect_moonscript_prefix(cleaned)

      emit_method_calls(path, content, cleaned, include_callee, handler_bodies, app_vars, app_paths)
      emit_match_calls(path, content, cleaned, include_callee, handler_bodies, app_vars, app_paths)
      emit_table_routes(path, content, cleaned, include_callee, handler_bodies)
      emit_moonscript_routes(path, content, cleaned, include_callee, moon_prefix)
    end

    # Lapis projects typically bind their application to a `local app`,
    # but production code uses any variable name — `users_app`,
    # `api_app`, `dashboard` — and Lapis's own README opens with
    # `local app = lapis.Application()`. We surface every such
    # binding and accept `<var>:<verb>(...)` route calls against
    # them, falling back to the bare `app` identifier when no
    # binding is detected so legacy files keep working.
    private def detect_app_vars(cleaned : String) : Array(String)
      vars = Set(String).new
      vars << "app"
      cleaned.scan(APP_VAR_RE) do |match|
        name = match[1]
        next if name == "local"
        vars << name
      end
      vars.to_a
    end

    # Sub-apps declare their mount prefix as `app.path = "/api/users"`.
    # When the app is `include`d by a parent every route is served
    # under that prefix, so `app:match("users", "", ...)` resolves to
    # `/api/users` and `app:match("user", "/:id", ...)` to
    # `/api/users/:id`. We map each application variable to its prefix
    # and only keep the binding when the variable is a known app var,
    # so unrelated `*.path` assignments (`parsed_url.path = ...`,
    # `manifest.path = ...`) never pollute the lookup.
    private def detect_app_paths(cleaned : String, app_vars : Array(String)) : Hash(String, String)
      known = app_vars.to_set
      paths = {} of String => String
      cleaned.scan(APP_PATH_RE) do |match|
        var = match[1]
        next unless known.includes?(var)
        paths[var] = match[3]
      end
      paths
    end

    # MoonScript Lapis controllers declare their mount prefix as a
    # class field — `@path: "/account"` — the MoonScript analogue of
    # Lua's `app.path = "/account"`. Without it every included
    # controller's `[list: "/list"]` route collapses to a bare `/list`
    # and distinct controllers' routes dedupe into one. We take the
    # first `@path` literal in the file (one Application class per file
    # is the universal convention) and prefix the file's MoonScript
    # class actions with it.
    private def detect_moonscript_prefix(cleaned : String) : String
      if match = cleaned.match(MOON_PATH_RE)
        match[2]
      else
        ""
      end
    end

    private def app_var_alternation(app_vars : Array(String)) : String
      app_vars.map { |v| Regex.escape(v) }.join("|")
    end

    # `app:get "/path"`, `app:post("/path", handler)`, etc.
    # Also handles the named form `app:get("name", "/path", handler)`
    # documented in Lapis's README — when the first string isn't a
    # path, look for the second.
    private def emit_method_calls(path : String,
                                  content : String,
                                  cleaned : String,
                                  include_callee : Bool,
                                  handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody),
                                  app_vars : Array(String),
                                  app_paths : Hash(String, String))
      alt = app_var_alternation(app_vars)
      pattern = @method_call_regexes[alt] ||= /\b(#{alt})\s*[:.]\s*(get|post|put|delete|patch|head|options)\s*\(?\s*(['"])([^'"]*)\3(?:\s*,\s*(['"])([^'"]*)\5)?/
      cleaned.scan(pattern) do |match|
        var = match[1]
        verb = match[2].upcase
        next unless HTTP_METHODS.includes?(verb)
        first = match[4]
        second = match[6]?

        relative : String? = nil
        after_url = match.begin(0) || 0
        if first.starts_with?("/")
          # Either `app:get("/path", handler)` or the
          # `app:get("/path", "named_handler_name")` string-handler form.
          # Stop the callee search just past the first string so the
          # named handler lookup in `route_call_callees` still works.
          relative = first
          after_url = (match.end(4) || 0) + 1
        elsif !second.nil?
          # Lapis's named-route form: `app:get("name", "/path", handler)`.
          # The first arg is the route name, not the URL — the second
          # string is the (possibly empty, prefix-relative) path.
          relative = second
          after_url = (match.end(6) || 0) + 1
        end
        next if relative.nil?

        url = resolve_url(app_paths[var]?, relative)
        route_offset = match.begin(0) || 0
        callees = include_callee ? route_call_callees(path, content, route_offset, after_url, handler_bodies) : [] of Noir::LuaCalleeExtractor::Entry
        emit_endpoint(path, content, route_offset, url, [verb], callees)
      end
    end

    # `app:match("/path", handler)` — any HTTP method.
    # `app:match("name", "/path", handler)` — named route.
    private def emit_match_calls(path : String,
                                 content : String,
                                 cleaned : String,
                                 include_callee : Bool,
                                 handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody),
                                 app_vars : Array(String),
                                 app_paths : Hash(String, String))
      alt = app_var_alternation(app_vars)
      pattern = @match_call_regexes[alt] ||= /\b(#{alt})\s*[:.]\s*match\s*\(?\s*(['"])([^'"]*)\2(?:\s*,\s*(['"])([^'"]*)\4)?/
      cleaned.scan(pattern) do |match|
        var = match[1]
        first = match[3]
        second = match[5]?
        relative = if first.starts_with?("/")
                     # `app:match("/path", handler)` — first arg is the path.
                     first
                   elsif !second.nil?
                     # `app:match("name", "/path", handler)` — named route;
                     # second arg is the (possibly empty) prefix-relative path.
                     second
                   else
                     next
                   end
        url = resolve_url(app_paths[var]?, relative)
        route_offset = match.begin(0) || 0
        url_end = match.end(0) || route_offset
        methods = match_methods(cleaned, route_offset, url_end)
        callees = include_callee ? route_call_callees(path, content, route_offset, url_end, handler_bodies) : [] of Noir::LuaCalleeExtractor::Entry
        emit_endpoint(path, content, route_offset, url, methods, callees)
      end
    end

    # `app:match` dispatches on any HTTP method unless its handler is an
    # inline `respond_to({ GET = ..., POST = ... })` table, which limits
    # the route to the verbs it names. Pulling those verbs out turns the
    # default all-methods fan-out into the real, smaller set and drops the
    # phantom PUT/DELETE/PATCH endpoints. The alias form `r2(require ...)`
    # carries no inline verbs (they live in the required module), so it
    # correctly falls through to the full method set.
    private def match_methods(cleaned : String, route_offset : Int32, url_end : Int32) : Array(String)
      search_limit, _ = route_call_limits(cleaned, route_offset, url_end)
      region = cleaned[route_offset...search_limit]? || ""
      if region.includes?("respond_to")
        verbs = scan_respond_to_verbs(region)
        return verbs unless verbs.empty?
      end
      FALLBACK_METHODS
    end

    # Pull the HTTP verbs a `respond_to` table names. The verb must sit in
    # a table-key position — directly after the opening `(`/`{`, a `,`
    # separator, or a newline — so a verb-shaped token buried inside a
    # handler body (`local POST = …`, a `"POST: "` string, a nested
    # `{ DELETE = true }`) is not miscounted as a dispatched method.
    private def scan_respond_to_verbs(region : String) : Array(String)
      verbs = [] of String
      region.scan(/[\n{,(]\s*(GET|POST|PUT|DELETE|PATCH|HEAD|OPTIONS)\b\s*[=:]/) do |match|
        verb = match[1].upcase
        verbs << verb unless verbs.includes?(verb)
      end
      verbs
    end

    # `["/path"] = "handler"` and `["/path"] = function(self) ... end`
    # — application-table style.
    private def emit_table_routes(path : String,
                                  content : String,
                                  cleaned : String,
                                  include_callee : Bool,
                                  handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody))
      pattern = /\[\s*(['"])([^'"]+)\1\s*\]\s*=/
      cleaned.scan(pattern) do |match|
        url = match[2]
        next unless url.starts_with?("/")

        route_offset = match.begin(0) || 0
        after_assignment = match.end(0) || route_offset
        callees = include_callee ? table_route_callees(path, content, after_assignment, handler_bodies) : [] of Noir::LuaCalleeExtractor::Entry
        emit_endpoint(path, content, route_offset, url, FALLBACK_METHODS, callees)
      end
    end

    # MoonScript class actions come in several shapes, all keyed by the
    # route path:
    #
    #   "/path": =>                              -- inline arrow (any verb)
    #   [name: "/path"]: =>                      -- named, inline arrow
    #   [name: "/path"]: respond_to { GET: => }  -- verb-specific handlers
    #   [name: "/path"]: capture_errors_json =>  -- wrapped arrow
    #   [name: "/path"]: capture_errors_json respond_to { ... }
    #
    # The earlier implementation only matched the two inline-arrow forms,
    # dropping every `respond_to` / wrapped handler — the dominant idiom
    # in real MoonScript Lapis apps. We now match the route header
    # regardless of what follows the `:` and inspect the action region to
    # recover the HTTP verbs (from a `respond_to` block) and callees.
    private def emit_moonscript_routes(path : String, content : String, cleaned : String, include_callee : Bool, moon_prefix : String)
      # Bracketed named routes `[name: "/path"]:` are unambiguous Lapis
      # syntax, so we accept any action body. Bare `"/path":` keys are
      # only treated as routes when the path is rooted and the body
      # carries an action marker (`=>` / `respond_to`), so string→string
      # config tables in non-route files are not mistaken for endpoints.
      named = /(?:^|\n)[ \t]*\[\s*[A-Za-z_]\w*\s*:\s*(['"])([^'"]+)\1\s*\]\s*:/
      cleaned.scan(named) do |match|
        url = match[2]
        next unless url.starts_with?("/")
        emit_moonscript_route(path, content, cleaned, include_callee, moon_prefix, url,
          match.begin(2) || match.begin(0) || 0, match.end(0) || 0, require_action: false)
      end

      simple = /(?:^|\n)[ \t]*(['"])(\/[^'"]*)\1\s*:/
      cleaned.scan(simple) do |match|
        url = match[2]
        emit_moonscript_route(path, content, cleaned, include_callee, moon_prefix, url,
          match.begin(2) || match.begin(0) || 0, match.end(0) || 0, require_action: true)
      end
    end

    private def emit_moonscript_route(path : String, content : String, cleaned : String,
                                      include_callee : Bool, moon_prefix : String, url : String,
                                      route_offset : Int32, value_start : Int32, require_action : Bool)
      region = Noir::LuaCalleeExtractor.moonscript_value_region(cleaned, value_start)
      region_text = region ? region[0] : ""
      return if require_action && !moonscript_action?(region_text)

      methods = moonscript_methods(region_text)
      callees = include_callee ? moonscript_route_callees(path, content, value_start) : [] of Noir::LuaCalleeExtractor::Entry
      emit_endpoint(path, content, route_offset, resolve_url(moon_prefix, url), methods, callees)
    end

    # Decide whether a bare `"/path":` key is a route. Its value is an
    # action when it is an arrow (`=>`), a `respond_to` block, or a
    # handler expression — `require "lapis.console" .make!`,
    # `capture_errors_json with_params {...}, (p) =>`, an action class.
    # Those all begin with an identifier/`@`. A value that opens with a
    # string or number literal (`"/old": "/new"`) is a config-table
    # entry, not a route, so it is rejected — guarding the broadened
    # bare-key match against string→string maps in non-route files.
    private def moonscript_action?(region_text : String) : Bool
      return true if region_text.includes?("=>") || region_text.includes?("respond_to")
      stripped = region_text.lstrip
      return false if stripped.empty?
      first = stripped[0]
      first.ascii_letter? || first == '_' || first == '@'
    end

    # Recover the HTTP verbs a MoonScript action serves. A
    # `respond_to { GET: =>, POST: => }` block names its verbs
    # explicitly; a bare arrow handles every method, so fall back to the
    # full verb set.
    private def moonscript_methods(region_text : String) : Array(String)
      if region_text.includes?("respond_to")
        verbs = scan_respond_to_verbs(region_text)
        return verbs unless verbs.empty?
      end
      FALLBACK_METHODS
    end

    private def emit_endpoint(path : String, content : String, offset : Int32,
                              url : String, methods : Array(String),
                              callees : Array(Noir::LuaCalleeExtractor::Entry) = [] of Noir::LuaCalleeExtractor::Entry)
      url = normalize_lapis_url(url)
      params = extract_path_params(url)
      line = line_for_offset(content, offset)
      details = Details.new(PathInfo.new(path, line))
      methods.each do |verb|
        endpoint_params = params.map { |p| Param.new(p.name, p.value, p.param_type) }
        endpoint = Endpoint.new(url, verb, endpoint_params, details)
        Noir::LuaCalleeExtractor.attach_to(endpoint, callees) unless callees.empty?
        @result << endpoint
      end
    end

    private def route_call_callees(path : String,
                                   content : String,
                                   route_offset : Int32,
                                   after_url : Int32,
                                   handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody)) : Array(Noir::LuaCalleeExtractor::Entry)
      search_limit, body_limit = route_call_limits(content, route_offset, after_url)
      if body = Noir::LuaCalleeExtractor.extract_function_after(content, after_url, search_limit, body_limit)
        body_text, start_line = body
        return Noir::LuaCalleeExtractor.callees_for_body(body_text, path, start_line)
      end

      if handler_name = string_handler_after(content, after_url, search_limit)
        return callees_for_named_handler(handler_name, handler_bodies)
      end

      if handler_name = identifier_handler_after(content, after_url, search_limit)
        return callees_for_named_handler(handler_name, handler_bodies)
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def table_route_callees(path : String,
                                    content : String,
                                    after_assignment : Int32,
                                    handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody)) : Array(Noir::LuaCalleeExtractor::Entry)
      value_start = skip_ws(content, after_assignment)
      if starts_with_keyword?(content, value_start, "function")
        if body = Noir::LuaCalleeExtractor.extract_function_at(content, value_start)
          body_text, start_line = body
          return Noir::LuaCalleeExtractor.callees_for_body(body_text, path, start_line)
        end
      elsif handler_name = string_literal_at(content, value_start)
        return callees_for_named_handler(handler_name, handler_bodies)
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def moonscript_route_callees(path : String, content : String, value_start : Int32) : Array(Noir::LuaCalleeExtractor::Entry)
      if region = Noir::LuaCalleeExtractor.moonscript_value_region(content, value_start)
        body_text, start_line = region
        return Noir::LuaCalleeExtractor.callees_for_body(body_text, path, start_line)
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def callees_for_named_handler(handler_name : String,
                                          handler_bodies : Hash(String, Noir::LuaCalleeExtractor::FunctionBody)) : Array(Noir::LuaCalleeExtractor::Entry)
      if body = handler_bodies[handler_name]?
        return Noir::LuaCalleeExtractor.callees_for_body(body[:body], body[:path], body[:start_line])
      end

      [] of Noir::LuaCalleeExtractor::Entry
    end

    private def route_call_limits(content : String, route_offset : Int32, after_url : Int32) : Tuple(Int32, Int32)
      if open_paren = first_open_paren_before(content, route_offset, after_url)
        if close_paren = Noir::LuaCalleeExtractor.find_matching_delimiter(content, open_paren, '(', ')')
          return {close_paren, close_paren}
        end
      end

      line_end = content.index('\n', after_url) || content.size
      {line_end, content.size}
    end

    private def first_open_paren_before(content : String, start_index : Int32, end_index : Int32) : Int32?
      cursor = start_index
      while cursor < end_index && cursor < content.size
        return cursor if content[cursor] == '('
        cursor += 1
      end

      nil
    end

    private def string_handler_after(content : String, start_index : Int32, limit : Int32) : String?
      cursor = skip_ws_and_commas(content, start_index)
      return if cursor >= limit

      string_literal_at(content, cursor)
    end

    private def identifier_handler_after(content : String, start_index : Int32, limit : Int32) : String?
      cursor = skip_ws_and_commas(content, start_index)
      return if cursor >= limit
      return unless identifier_start?(content[cursor])

      ident_start = cursor
      cursor += 1
      while cursor < limit && cursor < content.size && identifier_part?(content[cursor])
        cursor += 1
      end

      trailing = skip_ws(content, cursor)
      return if trailing < limit && content[trailing] == '('

      content[ident_start...cursor]
    end

    private def string_literal_at(content : String, index : Int32) : String?
      return if index >= content.size
      quote = content[index]
      return unless quote == '"' || quote == '\''

      cursor = index + 1
      escaped = false
      value = String::Builder.new
      while cursor < content.size
        char = content[cursor]
        if escaped
          value << char
          escaped = false
        elsif char == '\\'
          escaped = true
        elsif char == quote
          return value.to_s
        else
          value << char
        end
        cursor += 1
      end

      nil
    end

    private def skip_ws_and_commas(content : String, index : Int32) : Int32
      cursor = index
      while cursor < content.size && (content[cursor].whitespace? || content[cursor] == ',')
        cursor += 1
      end
      cursor
    end

    private def skip_ws(content : String, index : Int32) : Int32
      cursor = index
      while cursor < content.size && content[cursor].whitespace?
        cursor += 1
      end
      cursor
    end

    private def starts_with_keyword?(content : String, index : Int32, keyword : String) : Bool
      return false unless content[index, keyword.size]? == keyword
      before = index > 0 ? content[index - 1] : '\0'
      after_index = index + keyword.size
      after = after_index < content.size ? content[after_index] : '\0'
      !identifier_part?(before) && !identifier_part?(after)
    end

    private def identifier_start?(char : Char) : Bool
      char.ascii_letter? || char == '_'
    end

    private def identifier_part?(char : Char) : Bool
      char.ascii_alphanumeric? || char == '_'
    end

    # Returns the equals-sign count for a Lua long-bracket opener at
    # `index` — `[[` returns 0, `[=[` returns 1, `[==[` returns 2,
    # etc. Returns `nil` if `index` isn't an opener.
    private def lua_long_bracket_open?(chars : Array(Char), index : Int32) : Int32?
      return if chars[index]? != '['
      level = 0
      cursor = index + 1
      while cursor < chars.size && chars[cursor] == '='
        level += 1
        cursor += 1
      end
      return if cursor >= chars.size || chars[cursor] != '['
      level
    end

    private def lua_long_bracket_close?(chars : Array(Char), index : Int32, level : Int32) : Bool
      return false if chars[index]? != ']'
      cursor = index + 1
      level.times do
        return false if cursor >= chars.size || chars[cursor] != '='
        cursor += 1
      end
      cursor < chars.size && chars[cursor] == ']'
    end

    # Join a sub-app's `app.path` prefix (if any) with a route's
    # declared pattern. Lapis concatenates the two strings, so an empty
    # pattern collapses to the bare prefix (`/api/users`) and a
    # slash-prefixed pattern appends cleanly. The final normalisation in
    # `normalize_lapis_url` collapses any `//` the join introduces.
    private def resolve_url(prefix : String?, relative : String) : String
      prefix ||= ""
      combined = if relative.empty?
                   prefix
                 elsif prefix.empty?
                   relative
                 elsif relative.starts_with?("/")
                   "#{prefix}#{relative}"
                 else
                   "#{prefix}/#{relative}"
                 end
      combined = "/#{combined}" unless combined.starts_with?("/")
      combined
    end

    # Lapis route patterns are not concrete URLs: a param can carry a
    # Lua-pattern constraint (`:id[%d]`, `:slug[%w%-]`) and any portion
    # of the path can be wrapped in an optional group (`(/page/:page)`,
    # `(#:anchor)`). Strip the constraints back to the bare param name
    # and peel every (possibly nested) optional group down to its
    # required base, matching the convention noir's Rails analyzer uses,
    # then collapse the `//` and trailing-`/` artifacts that remain.
    private def normalize_lapis_url(url : String) : String
      result = url.gsub(/([:*][A-Za-z_]\w*)\[[^\]]*\]/, "\\1")
      result = strip_optional_groups(result) if result.includes?('(')
      result = result.gsub(%r{/{2,}}, "/")
      result = result.rchop('/') if result.size > 1 && result.ends_with?('/')
      result = "/" if result.empty?
      result
    end

    # Peel Lapis optional groups `(...)` down to their required base in a
    # single linear pass (depth-tracked): characters inside any (possibly
    # nested) group are dropped. This is equivalent to repeatedly removing
    # the innermost group on balanced input but runs in O(n) — a repeated
    # `gsub(/\([^()]*\)/, "")` loop is O(n²) on deeply nested patterns and
    # lets a crafted route string (`/x(((((…)))))`) stall a scan.
    private def strip_optional_groups(url : String) : String
      result = String::Builder.new
      depth = 0
      url.each_char do |char|
        case char
        when '('
          depth += 1
        when ')'
          depth -= 1 if depth > 0
        else
          result << char if depth == 0
        end
      end
      result.to_s
    end

    private def extract_path_params(url : String) : Array(Param)
      params = [] of Param
      url.scan(/[:*]([A-Za-z_]\w*)/) do |match|
        params << Param.new(match[1], "", "path")
      end
      params
    end

    private def strip_lua_comments(text : String) : String
      result = String::Builder.new
      i = 0
      chars = text.chars
      in_string = false
      string_quote = '\0'

      while i < chars.size
        c = chars[i]

        if in_string
          if c == '\\' && i + 1 < chars.size
            result << c
            result << chars[i + 1]
            i += 2
            next
          elsif c == string_quote
            in_string = false
          end
          result << c
          i += 1
          next
        end

        if c == '"' || c == '\''
          in_string = true
          string_quote = c
          result << c
          i += 1
          next
        end

        # Lua long-bracket string: `[[ ... ]]` or `[=[ ... ]=]`. Code
        # generators such as `lapis.cmd.templates.application` ship
        # MoonScript / Lua templates inside these here-strings, and
        # patterns like `"/": =>` or `app:get("/", ...)` *inside the
        # template* should not be surfaced as live endpoints in the
        # generator script.
        if c == '[' && (bracket_level = lua_long_bracket_open?(chars, i))
          opener_size = bracket_level + 2
          opener_size.times { result << ' ' }
          i += opener_size
          while i < chars.size
            if chars[i] == ']' && lua_long_bracket_close?(chars, i, bracket_level)
              closer_size = bracket_level + 2
              closer_size.times { result << ' ' }
              i += closer_size
              break
            end
            result << (chars[i] == '\n' ? '\n' : ' ')
            i += 1
          end
          next
        end

        # Lua / MoonScript line comment: --
        # MoonScript also supports `--` and Lua block comments use --[[ ... ]]
        if i + 1 < chars.size && c == '-' && chars[i + 1] == '-'
          # Block form: --[[ ... ]], --[=[ ... ]=], --[==[ ... ]==], ...
          # Use the leveled detector so a `--[=[ ... ]=]` comment isn't misread
          # as a line comment (which leaks its body as phantom routes).
          if comment_level = lua_long_bracket_open?(chars, i + 2)
            opener_size = comment_level + 2
            (opener_size + 2).times { result << ' ' } # blank `--` + opener
            i += 2 + opener_size
            while i < chars.size
              if chars[i] == ']' && lua_long_bracket_close?(chars, i, comment_level)
                (comment_level + 2).times { result << ' ' }
                i += comment_level + 2
                break
              end
              result << (chars[i] == '\n' ? '\n' : ' ')
              i += 1
            end
            next
          end
          # Line form
          while i < chars.size && chars[i] != '\n'
            result << ' '
            i += 1
          end
          next
        end

        result << c
        i += 1
      end

      result.to_s
    end

    private def line_for_offset(content : String, offset : Int32) : Int32
      return 1 if offset <= 0
      limit = offset > content.size ? content.size : offset
      count = 1
      # each_char advances in O(1); the old content[i] loop was O(n^2) on
      # multi-byte (UTF-8) content, stalling large CJK files with many routes.
      content.each_char_with_index do |ch, i|
        break if i >= limit
        count += 1 if ch == '\n'
      end
      count
    end
  end
end
